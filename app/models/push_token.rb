class PushToken < ApplicationRecord
  belongs_to :user

  validates :token,     presence: true
  validates :device_id, presence: true
  validates :platform,  presence: true, inclusion: { in: %w[ios android] }
end
