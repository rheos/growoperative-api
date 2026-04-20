class SubnetMembership < ApplicationRecord
  belongs_to :user
  belongs_to :subnet
  belongs_to :joined_via_invitation, class_name: 'Invitation', optional: true

  validates :user_id, uniqueness: { scope: :subnet_id }
  validate :at_most_one_primary_per_user

  scope :primary, -> { where(is_primary: true) }

  private

  def at_most_one_primary_per_user
    return unless is_primary
    scope = SubnetMembership.where(user_id: user_id, is_primary: true)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:is_primary, 'already set on another membership') if scope.exists?
  end
end
