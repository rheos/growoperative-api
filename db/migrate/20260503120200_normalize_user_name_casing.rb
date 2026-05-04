class NormalizeUserNameCasing < ActiveRecord::Migration[5.2]
  # Normalize any pre-existing mixed-case user_name to lowercase canonical
  # form. The User model gains a before_validation callback in this same
  # patch to keep new writes lowercase going forward. Audit confirmed zero
  # collisions in dev; production must run the audit query before deploy
  # (foaf-auth/docs/audits/user-data-pre-foaf-id-audit.md → "Production
  # dry-run").
  def up
    execute <<~SQL.squish
      UPDATE users
         SET user_name = LOWER(user_name)
       WHERE user_name <> LOWER(user_name)
    SQL
  end

  def down
    # Lowercasing is not reversible; no-op rollback. The before_validation
    # callback in the User model will continue to lowercase new writes
    # regardless of this migration's state.
  end
end
