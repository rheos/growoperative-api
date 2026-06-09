class CreateInvitationRedemptions < ActiveRecord::Migration[5.2]
  # One row per (multi-use invitation, redeemer). A multi-use code can't
  # use the single `accepted_id` int to hold N redeemers, so this join
  # table records each. The unique index on [invitation_id, user_id] is the
  # duplicate-redemption guard that makes both write sites (the User
  # after_create callback and OnboardingService#apply_effects!) idempotent.
  def change
    create_table :invitation_redemptions, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.bigint :invitation_id
      t.bigint :user_id
      t.datetime :redeemed_at
      t.timestamps
    end

    add_index :invitation_redemptions, [:invitation_id, :user_id], unique: true,
              name: 'index_invitation_redemptions_on_invitation_and_user'
    add_index :invitation_redemptions, :user_id
  end
end
