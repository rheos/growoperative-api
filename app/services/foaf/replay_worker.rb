# frozen_string_literal: true

# Foaf::ReplayWorker — resolves durable Rails publication records that never
# reached a known FOAF success.
#
# Limit-update outbox rows run first because an unposted capacity increase may
# be required before a retained payment can succeed.
#
# Balance-write flow per TrustlineTransaction (see Foaf::Publisher#publish_payment):
#   foaf_direction: 'sent'     -> publish_payment(from: initiated_by, to: other)
#   foaf_direction: 'received' -> publish_settlement(payer: initiated_by, payee: other)
#   foaf_direction: nil        -> skip (historical row or legacy data)
#
# Foaf::Publisher first reads by the deterministic
# idempotency key (or retained pending-transfer id), and only creates/confirms
# when FOAF proves that step is still needed. A known 4xx rejection is terminal
# and is not retried automatically.
#
# With FOAF_SHARED_WRITES=false, ReplayWorker performs no network mutation and
# reports the retained payment/limit buffers. Re-enabling the flag resumes the
# same idempotent gem path.
#
# Adjustment-direction rows (record_debt / record_receipt) replay through the
# same primitives. If FOAF rejects the replay for a capacity reason — e.g.
# the limit-extend settlement rewrites haven't landed yet — the row remains
# unposted. That's visible as drift via /v1/debug/foaf/reconcile.
module Foaf
  module ReplayWorker
    module_function

    def run(limit: 100)
      return { skipped: "foaf_write_disabled" } unless Foaf::Config.foaf_write_enabled?
      return buffered_result unless Foaf::Config.shared_writes?

      publisher = Foaf::Publisher.new
      results = {
        attempted: 0,
        posted: 0,
        still_unposted: 0,
        skipped: 0,
        limit_attempted: 0,
        limit_posted: 0,
        limit_still_unposted: 0,
        limit_skipped: 0
      }

      limit_entries_processed = replay_limit_updates(
        publisher,
        results,
        limit: limit
      )
      remaining = [limit - limit_entries_processed, 0].max

      scope = TrustlineTransaction
                .where(foaf_posted_at: nil)
                .where.not(foaf_direction: nil)
                .includes(trustline: [:user_a, :user_b], initiated_by: [])
                .order(:created_at)
                .limit(remaining)

      scope.each do |tx|
        if tx.foaf_write_state == "rejected"
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
            publisher.publish_payment(
              trustline, tx.amount, initiator, counterparty,
              description: tx.description, order: tx.order,
              operation: infer_operation(tx), tx_row: tx,
            )
          when "received"
            publisher.publish_settlement(
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

    def replay_limit_updates(publisher, results, limit:)
      entries = FoafOutboxEntry
                  .active
                  .trustline_updates
                  .includes(trustline: [:user_a, :user_b])
                  .oldest_first
                  .limit(limit)
                  .to_a

      entries.each do |entry|
        if entry.foaf_write_state == "rejected"
          results[:skipped] += 1
          results[:limit_skipped] += 1
          next
        end

        results[:attempted] += 1
        results[:limit_attempted] += 1

        begin
          publisher.publish_trustline_update(
            entry.trustline,
            nil,
            outbox_entry: entry
          )
        rescue StandardError => e
          Rails.logger.warn(
            "[FOAF Replay] limit outbox #{entry.id} raised: #{e.message}"
          )
        end

        if entry.reload.foaf_posted_at.present?
          results[:posted] += 1
          results[:limit_posted] += 1
        else
          results[:still_unposted] += 1
          results[:limit_still_unposted] += 1
        end
      end

      entries.length
    end

    def buffered_result
      payment_count = TrustlineTransaction
                        .where(foaf_posted_at: nil)
                        .where.not(foaf_direction: nil)
                        .where(
                          "foaf_write_state IS NULL OR foaf_write_state != ?",
                          "rejected"
                        )
                        .count
      limit_count = FoafOutboxEntry
                      .active
                      .trustline_updates
                      .where.not(foaf_write_state: "rejected")
                      .count

      {
        skipped: "shared_writes_disabled",
        buffered_payments: payment_count,
        buffered_limit_updates: limit_count
      }
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
