class AddAppOnboardingStatusToInvitations < ActiveRecord::Migration[5.2]
  # Job 11: gives the v1 onboarding endpoint a place to record the
  # transactional outcome of applying app-specific effects (subnet
  # membership, role assignment, relationship creation, app counters).
  #
  # `app_onboarding_status` semantics (master plan §1):
  #   pending     — auth invite accepted, app effects not yet applied
  #   completed   — app effects applied successfully
  #   failed      — retryable operational failure
  #   rejected    — terminal app policy refusal (don't auto-retry)
  #   expired     — 30-day onboarding window elapsed
  #   not_applicable — pure identity/contact invite, no app onboarding
  def change
    add_column :invitations, :app_onboarding_status, :string, default: 'pending', null: false
    add_column :invitations, :app_onboarding_rejection_code, :string
    add_column :invitations, :app_onboarding_completed_at, :datetime

    add_index :invitations, [:app_onboarding_status, :user_id],
              name: 'index_invitations_on_app_onboarding_status_user'

    # Backfill: every invitation already in `accepted` state has had its
    # app effects applied through the legacy signup / accept_invitation
    # path, so mark those completed. Pre-launch DB, low row count —
    # inline backfill per `feedback_migration_sizing` memory.
    reversible do |dir|
      dir.up do
        execute(<<~SQL)
          UPDATE invitations
          SET app_onboarding_status = 'completed',
              app_onboarding_completed_at = COALESCE(updated_at, NOW())
          WHERE status = 1
        SQL
      end
    end
  end
end
