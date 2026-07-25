# frozen_string_literal: true

# Ledger hooks that publish app operations to FOAF.
# Balance-moving calls run after their failure-buffer row is recorded; trustline
# limit updates currently publish directly. Errors never escape the hook.
#
# Runs synchronously (not threaded) to avoid race conditions on
# keypair generation. The HTTP calls to FOAF are local and fast.

module Foaf
  module LedgerHooks
    module_function

    def publisher
      @publisher ||= Foaf::Publisher.new
    end

    # Call after a trustline is created or updated.
    def after_trustline_save(trustline, current_user)
      return unless Foaf::Config.foaf_write_enabled?

      publisher.publish_trustline_update(trustline, current_user)
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Trustline publish failed: #{e.message}")
    end

    # Call after process_payment! succeeds. On successful FOAF confirm the
    # publisher writes foaf_operation_id + foaf_posted_at onto tx_row. On failure
    # tx_row is left unposted for Foaf::ReplayWorker to pick up.
    def after_payment(trustline, amount, from_user, to_user, description: nil, order: nil, operation: "payment", metadata: nil, tx_row: nil)
      return unless Foaf::Config.foaf_write_enabled?

      publisher.publish_payment(trustline, amount, from_user, to_user,
                                description: description, order: order, operation: operation, metadata: metadata, tx_row: tx_row)
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Payment publish failed: #{e.message}")
    end

    # Call after settle_payment! succeeds. Settlement is the inverse of FOAF's
    # transfer primitive — see project_settlement_vs_extension memory. The
    # publisher auto-expands the (swapped) sender's credit room before the
    # transfer so settling existing debt isn't blocked by limits that don't
    # apply to repayment.
    def after_settlement(trustline, amount, payer, payee, description: nil, order: nil, operation: "settlement", metadata: nil, tx_row: nil)
      return unless Foaf::Config.foaf_write_enabled?

      publisher.publish_settlement(trustline, amount, payer, payee,
                                   description: description, order: order, operation: operation, metadata: metadata, tx_row: tx_row)
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Settlement publish failed: #{e.message}")
    end

    # Run reconciliation for all active trustlines.
    def reconcile_all
      return unless Foaf::Config.foaf_write_enabled?

      results = { matches: 0, discrepancies: 0, errors: 0 }

      Trustline.where(is_active: true).find_each do |tl|
        result = publisher.reconcile_trustline(tl)
        if result.nil?
          results[:matches] += 1
        elsif result[:error]
          results[:errors] += 1
        else
          results[:discrepancies] += 1
        end
      end

      Rails.logger.info("[FOAF Publisher] Reconciliation: #{results}")
      results
    end
  end
end
