class AddMultiUseFlagsToInvitations < ActiveRecord::Migration[5.2]
  # Multi-use invitation codes: a `multi_use` code can be redeemed by many
  # people and never goes terminal (`status` stays pending). `disabled_at`
  # is the on/off switch — null = active, set = turned off — matching the
  # `deleted_at`/`disabled_at` timestamp-as-flag convention on users.
  #
  # Boolean default + nullable timestamp means no backfill: every existing
  # row reads as single-use (multi_use = false) and active (disabled_at nil).
  def change
    add_column :invitations, :multi_use, :boolean, null: false, default: false
    add_column :invitations, :disabled_at, :datetime
  end
end
