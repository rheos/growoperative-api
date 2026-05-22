# Append-only audit trail for security/accountability-sensitive actions.
#
# Any subsystem can record an event:
#
#   AuditLog.record(
#     action: "demo.reset",
#     actor_user: current_user,   # optional; sets actor_user_id + actor label
#     source: "api",              # api / rake / script
#     status: "succeeded",        # started / succeeded / failed
#     metadata: { snapshot_name: "default" },
#   )
#
# Recording must never break the action being audited, so .record rescues and
# logs rather than raising. Rows are never updated or deleted in normal flow.
class AuditLog < ApplicationRecord
  STATUSES = %w[started succeeded failed].freeze

  validates :action, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  def self.record(action:, actor: nil, actor_user: nil, source: nil, status: "succeeded", metadata: {})
    create!(
      action: action,
      actor: actor || actor_user&.user_name || "system",
      actor_user_id: actor_user&.id,
      source: source,
      status: status,
      metadata: metadata || {},
    )
  rescue StandardError => e
    # Auditing is best-effort: a logging failure must not abort the audited action.
    Rails.logger.error("[AuditLog] failed to record #{action.inspect} (#{status}): #{e.message}")
    nil
  end
end
