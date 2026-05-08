# frozen_string_literal: true

# Shadow hooks that wire into existing app operations.
# Called after the authoritative operation succeeds.
# Fire-and-forget — never raises, never blocks the app.
#
# Runs synchronously (not threaded) to avoid race conditions on
# keypair generation. The HTTP calls to FOAF are local and fast.

module Foaf
  module ShadowHooks
    module_function

    def shadow
      @shadow ||= Foaf::Shadow.new
    end

    # Call after a trustline is created or updated.
    def after_trustline_save(trustline, current_user)
      return unless Foaf::Config.shadow_mode?

      shadow.mirror_trustline_update(trustline, current_user)
    rescue StandardError => e
      Rails.logger.warn("[FOAF Shadow] Trustline mirror failed: #{e.message}")
    end

    # Call after process_payment! succeeds. On successful FOAF confirm the
    # mirror writes foaf_operation_id + foaf_posted_at onto tx_row. On failure
    # tx_row is left unposted for Foaf::ReplayWorker to pick up.
    def after_payment(trustline, amount, from_user, to_user, description: nil, order: nil, operation: "payment", metadata: nil, tx_row: nil)
      return unless Foaf::Config.shadow_mode?

      shadow.mirror_payment(trustline, amount, from_user, to_user,
                            description: description, order: order, operation: operation, metadata: metadata, tx_row: tx_row)
    rescue StandardError => e
      Rails.logger.warn("[FOAF Shadow] Payment mirror failed: #{e.message}")
    end

    # Call after settle_payment! succeeds. Settlement is the inverse of FOAF's
    # transfer primitive — see project_settlement_vs_extension memory. The
    # mirror auto-expands the (swapped) sender's credit room before the
    # transfer so settling existing debt isn't blocked by limits that don't
    # apply to repayment.
    def after_settlement(trustline, amount, payer, payee, description: nil, order: nil, operation: "settlement", metadata: nil, tx_row: nil)
      return unless Foaf::Config.shadow_mode?

      shadow.mirror_settlement(trustline, amount, payer, payee,
                                description: description, order: order, operation: operation, metadata: metadata, tx_row: tx_row)
    rescue StandardError => e
      Rails.logger.warn("[FOAF Shadow] Settlement mirror failed: #{e.message}")
    end

    # Run reconciliation for all active trustlines.
    def reconcile_all
      return unless Foaf::Config.shadow_mode?

      results = { matches: 0, discrepancies: 0, errors: 0 }

      Trustline.where(is_active: true).find_each do |tl|
        result = shadow.reconcile_trustline(tl)
        if result.nil?
          results[:matches] += 1
        elsif result[:error]
          results[:errors] += 1
        else
          results[:discrepancies] += 1
        end
      end

      Rails.logger.info("[FOAF Shadow] Reconciliation: #{results}")
      results
    end
  end
end
