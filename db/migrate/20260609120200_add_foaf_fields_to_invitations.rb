class AddFoafFieldsToInvitations < ActiveRecord::Migration[5.2]
  def change
    # Durable key for the authoritative FOAF (auth.foaf.io) invitation. Nullable:
    # legacy local-only rows and unsynced rows have no FOAF counterpart yet.
    # Non-unique index — a FOAF write may be retried, and we look up by this id
    # during reconciliation, not enforce uniqueness here.
    add_column :invitations, :auth_invitation_id, :string
    add_index :invitations, :auth_invitation_id

    # Mirrors FOAF's code-generation choice (e.g. pronounceable vs random) for
    # display/analytics. Set by dual-write; null for legacy local-only rows.
    add_column :invitations, :code_strategy, :string

    # Reconciliation handle: 'unsynced' | 'synced' | 'failed' | 'reconciled'
    # (see Invitation::FOAF_STATE_* constants). Nullable; internal infrastructure.
    add_column :invitations, :foaf_invitation_state, :string
  end
end
