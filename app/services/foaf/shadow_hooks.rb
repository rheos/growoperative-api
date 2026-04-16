# frozen_string_literal: true

# Shadow hooks that wire into existing app operations.
# Called after the authoritative operation succeeds.
# Fire-and-forget — never raises, never blocks the app.
#
# Usage: call these from controllers/models after the real operation completes.
# The shadow singleton handles all the FOAF communication.

module Foaf
  module ShadowHooks
    module_function

    def shadow
      @shadow ||= Foaf::Shadow.new
    end

    # Call after a trustline is created or updated.
    def after_trustline_save(trustline, current_user)
      return unless Foaf::Config.shadow_mode?

      Thread.new do
        shadow.mirror_trustline_update(trustline, current_user)
      rescue StandardError => e
        Rails.logger.warn("[FOAF Shadow] Background mirror failed: #{e.message}")
      end
    end

    # Call after process_payment! succeeds.
    def after_payment(trustline, amount, from_user, to_user, description: nil, order: nil)
      return unless Foaf::Config.shadow_mode?

      Thread.new do
        shadow.mirror_payment(trustline, amount, from_user, to_user,
                              description: description, order: order)
      rescue StandardError => e
        Rails.logger.warn("[FOAF Shadow] Background payment mirror failed: #{e.message}")
      end
    end

    # Run reconciliation for all active trustlines.
    # Call from a rake task or console.
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
