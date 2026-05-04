class AddFoafIdToUsers < ActiveRecord::Migration[5.2]
  # Adds the auth.foaf.io identity column to users. Sized at 36 chars for the
  # canonical UUID v4 representation. Inline backfill is safe per the
  # pre-launch / migration-sizing pattern documented for this codebase.
  # Audit: foaf-auth/docs/audits/user-data-pre-foaf-id-audit.md.
  def up
    add_column :users, :foaf_id, :string, limit: 36

    User.reset_column_information
    User.where(foaf_id: nil).find_each(batch_size: 500) do |user|
      user.update_columns(foaf_id: SecureRandom.uuid)
    end

    change_column_null :users, :foaf_id, false
    add_index :users, :foaf_id, unique: true
  end

  def down
    remove_index :users, :foaf_id
    remove_column :users, :foaf_id
  end
end
