class AddIdentityNameFieldsToUsers < ActiveRecord::Migration[5.2]
  # FoafIdentity-shaped fields the auth.foaf.io contract expects. All
  # nullable in Phase 2; the `users.name` column stays around as the
  # legacy source until name-mapping migration runs (job 31). Audit:
  # foaf-auth/docs/audits/user-data-pre-foaf-id-audit.md.
  def change
    add_column :users, :first_name,   :string
    add_column :users, :last_name,    :string
    add_column :users, :display_name, :string
  end
end
