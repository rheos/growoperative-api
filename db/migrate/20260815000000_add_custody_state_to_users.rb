# frozen_string_literal: true

# Track where each user's private key lives during the one-address-per-identity
# custody migration: "pending" (key still in railsbackend.users), "migrated"
# (adopted by the shared custodian, both key columns nulled), "error" (a check
# failed and the row was skipped for operator review).
#
# Deliberately a plain :string, NOT a MySQL ENUM. The three values are enforced
# in Ruby (the migrate_keys rake state machine), so this column type is portable
# to the Neon Postgres target — a bare varchar + btree index applies identically
# on MySQL 5.7 and Postgres 16.
class AddCustodyStateToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :custody_state, :string, default: "pending"
    add_index :users, :custody_state
  end
end
