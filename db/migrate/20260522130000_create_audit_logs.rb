# Generic append-only audit trail. Any subsystem can record an event via
# AuditLog.record(...). First consumer is demo reset (action "demo.reset"),
# which proved necessary after a reset wiped demo trade data with no record of
# who triggered it. Designed to be written to from controllers (with a user),
# rake tasks, and shell scripts (via rails runner).
class CreateAuditLogs < ActiveRecord::Migration[5.2]
  def change
    create_table :audit_logs do |t|
      t.string :action, null: false              # e.g. "demo.reset"
      t.string :status, null: false, default: "succeeded" # started / succeeded / failed
      t.string :source                            # api / rake / script
      t.string :actor                             # human-readable: username, "system:rake", "operator:ubuntu@host"
      t.bigint :actor_user_id                     # users.id when a real user is known
      t.json   :metadata                          # arbitrary context (snapshot, counts, error, ...)
      t.datetime :created_at, null: false
    end

    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
    add_index :audit_logs, :actor_user_id
  end
end
