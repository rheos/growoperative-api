namespace :foaf do
  # Job 51 Phase 1 — idempotent forward-reconcile of `unsynced` issuance rows
  # into FOAF (auth.foaf.io). When the dual-write in `generate_invitation`
  # couldn't reach FOAF (auto-generator path), it kept the local fallback code
  # and tagged the row `foaf_invitation_state = 'unsynced'` with no
  # `auth_invitation_id`. This sweep pushes those rows into FOAF so issuance
  # authority is consistent.
  #
  # Scope: redemption stays LOCAL in this phase. The local `invitation_code`
  # is the redemption key and is intentionally NOT overwritten — the FOAF row
  # this creates is the issuance-authority record, not the redemption key.
  # (Backfilling the redeemable code mirror is a later job / Phase 2.)
  #
  # Idempotent: only touches `unsynced` rows with a nil `auth_invitation_id`.
  # `synced` / `reconciled` / `failed` rows are skipped; re-running is a no-op.
  #
  # Gated by FOAF_AUTH_INVITE_BRIDGE_ENABLED (off => no-op, no FOAF calls).
  desc "Reconcile unsynced local invitation issuance rows into FOAF (Job 51)"
  task reconcile_invitation_issuance: :environment do
    summary = InvitationIssuanceReconciler.run
    puts "reconcile_invitation_issuance: #{summary.inspect}"
  end
end
