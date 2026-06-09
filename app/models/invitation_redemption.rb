class InvitationRedemption < ApplicationRecord
  # One row per (multi-use invitation, redeemer). The unique index on
  # [invitation_id, user_id] is the duplicate-redemption guard; the
  # validation surfaces it as a clean error and `find_or_create_by!`
  # against it makes both redemption write sites idempotent.
  belongs_to :invitation
  belongs_to :user

  validates :user_id, uniqueness: { scope: :invitation_id }
end
