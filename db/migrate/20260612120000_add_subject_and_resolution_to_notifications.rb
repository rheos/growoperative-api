class AddSubjectAndResolutionToNotifications < ActiveRecord::Migration[5.2]
  # Links a notification to the obligation object it announces (polymorphic
  # subject: ItemRequest, PendingPayment) and records when/why that obligation
  # stopped being outstanding. NULL resolved_at = live; set = resolved.
  #
  # All columns nullable, no backfill: every existing row reads as having no
  # subject and being unresolved, which is the correct legacy interpretation.
  #
  # No FK on subject_id — it is polymorphic across multiple tables.
  def change
    add_column :notifications, :subject_type,      :string
    add_column :notifications, :subject_id,        :bigint
    add_column :notifications, :resolved_at,       :datetime
    add_column :notifications, :resolution_reason, :string

    # Badge-count queries: unresolved notifications per recipient.
    add_index :notifications, [:recipient_id, :resolved_at],
              name: 'index_notifications_on_recipient_and_resolved'
    # Resolver lookups: all notifications pointing at one obligation object.
    add_index :notifications, [:subject_type, :subject_id],
              name: 'index_notifications_on_subject'
  end
end
