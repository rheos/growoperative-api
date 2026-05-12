class SubnetApplication < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :reviewed_by, class_name: 'User', foreign_key: :reviewed_by_user_id, optional: true
  belongs_to :created_subnet, class_name: 'Subnet', foreign_key: :created_subnet_id, optional: true

  validates :community_name, presence: true, length: { maximum: 120 }
  validates :location,       presence: true, length: { maximum: 120 }
  validates :contact_name,   presence: true, length: { maximum: 120 }
  validates :contact_email,  presence: true, length: { maximum: 254 },
                             format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :description,    length: { maximum: 4000 }, allow_blank: true
  validates :status,         inclusion: { in: STATUSES }

  scope :pending,  -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
end
