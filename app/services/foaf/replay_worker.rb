# frozen_string_literal: true

# Foaf::ReplayWorker — resolves TrustlineTransaction rows whose mirror to FOAF
# never reached a known success. A row qualifies when foaf_posted_at IS NULL.
#
# Flow per row (see Foaf::Shadow#mirror_payment):
#   foaf_direction: 'sent'     -> mirror_payment(from: initiated_by, to: other)
#   foaf_direction: 'received' -> mirror_settlement(payer: initiated_by, payee: other)
#   foaf_direction: nil        -> skip (historical row or legacy data)
#
# With FOAF_SHARED_WRITES=true, Foaf::Shadow first reads by the deterministic
# idempotency key (or retained pending-transfer id), and only creates/confirms
# when FOAF proves that step is still needed. It never falls back to the legacy
# writer. A known 4xx rejection is terminal and is not retried automatically.
#
# With FOAF_SHARED_WRITES=false, the existing legacy replay path is unchanged.
#
# Adjustment-direction rows (record_debt / record_receipt) replay through the
# same primitives. If FOAF rejects the replay for a capacity reason — e.g.
# the limit-extend settlement rewrites haven't landed yet — the row remains
# unposted. That's visible as drift via /v1/debug/foaf/reconcile.
module Foaf
  module ReplayWorker
    module_function

    def run(limit: 100)
      return { skipped: "shadow_mode_off" } unless Foaf::Config.shadow_mode?

      shadow = Foaf::Shadow.new
      scope = TrustlineTransaction
                .where(foaf_posted_at: nil)
                .where.not(foaf_direction: nil)
                .includes(trustline: [:user_a, :user_b], initiated_by: [])
                .order(:created_at)
                .limit(limit)

      results = { attempted: 0, posted: 0, still_unposted: 0, skipped: 0 }

      scope.each do |tx|
        if Foaf::Config.shared_writes? && tx.foaf_write_state == "rejected"
          results[:skipped] += 1
          next
        end

        trustline = tx.trustline
        initiator = tx.initiated_by
        unless trustline && initiator
          results[:skipped] += 1
          next
        end

        counterparty = trustline.other_user(initiator)

        results[:attempted] += 1
        begin
          case tx.foaf_direction
          when "sent"
            shadow.mirror_payment(
              trustline, tx.amount, initiator, counterparty,
              description: tx.description, order: tx.order,
              operation: infer_operation(tx), tx_row: tx,
            )
          when "received"
            shadow.mirror_settlement(
              trustline, tx.amount, initiator, counterparty,
              description: tx.description, order: tx.order,
              operation: infer_operation(tx), tx_row: tx,
            )
          else
            results[:skipped] += 1
            next
          end
        rescue StandardError => e
          Rails.logger.warn("[FOAF Replay] tx #{tx.id} raised: #{e.message}")
        end

        if tx.reload.foaf_posted_at.present?
          results[:posted] += 1
        else
          results[:still_unposted] += 1
        end
      end

      Rails.logger.info("[FOAF Replay] #{results}")
      results
    end

    # tx.transaction_type can be 'payment', 'adjustment', 'settlement' (on the
    # Rails side). FOAF only cares about the string as metadata — pass through.
    def infer_operation(tx)
      case tx.transaction_type
      when "adjustment" then "adjustment"
      when "settlement" then "settlement"
      else "payment"
      end
    end
  end
end
