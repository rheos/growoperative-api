class Notification < ApplicationRecord
  belongs_to :recipient, class_name: 'User'
  belongs_to :actor,     class_name: 'User', optional: true
  belongs_to :subject,   polymorphic: true,  optional: true

  validates :notification_type, presence: true
  validates :message,           presence: true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :unread,       -> { where(read: false) }
  scope :unresolved,   -> { where(resolved_at: nil) }

  PAGE_SIZE = 20

  def mark_read!
    return if read?
    update!(read: true, read_at: Time.current)
  end

  # Marks the underlying obligation as no longer outstanding. Idempotent:
  # the first resolution wins, later calls are no-ops.
  def resolve!(reason)
    return if resolved_at?
    update!(resolved_at: Time.current, resolution_reason: reason.to_s)
  end

  # Stable JSON shape consumed by the frontend.
  # Called from the controller — keeps serialization in one place.
  def as_inbox_json
    {
      id:                id,
      type:              notification_type,
      message:           message,
      actor_name:        actor_name,
      actor_avatar_url:  actor_avatar_url,
      target_type:       target_type,
      target_id:         target_id,
      target_screen:     target_screen,
      metadata:          metadata || {},
      read:              read,
      read_at:           read_at&.iso8601,
      created_at:        created_at.iso8601,
      subject_type:      subject_type,
      subject_id:        subject_id,
      resolved_at:       resolved_at&.iso8601,
      resolution_reason: resolution_reason,
      outstanding:       resolved_at.nil?
    }
  end
end
