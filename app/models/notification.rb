class Notification < ApplicationRecord
  belongs_to :recipient, class_name: 'User'
  belongs_to :actor,     class_name: 'User', optional: true

  validates :notification_type, presence: true
  validates :message,           presence: true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :unread,       -> { where(read: false) }

  PAGE_SIZE = 20

  def mark_read!
    return if read?
    update!(read: true, read_at: Time.current)
  end

  # Stable JSON shape consumed by the frontend.
  # Called from the controller — keeps serialization in one place.
  def as_inbox_json
    {
      id:               id,
      type:             notification_type,
      message:          message,
      actor_name:       actor_name,
      actor_avatar_url: actor_avatar_url,
      target_type:      target_type,
      target_id:        target_id,
      target_screen:    target_screen,
      metadata:         metadata || {},
      read:             read,
      read_at:          read_at&.iso8601,
      created_at:       created_at.iso8601
    }
  end
end
