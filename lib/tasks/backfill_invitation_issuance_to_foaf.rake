namespace :backfill do
  # Job 51 Phase 2 — backfill existing local invitation issuance metadata into
  # FOAF (auth.foaf.io). Thin wrapper around InvitationIssuanceBackfill; all the
  # per-row logic and the contract live in that service (and its spec).
  #
  # LIVE PENDING rows get a same-code FOAF reservation (the redeemability-
  # critical case); TERMINAL rows (accepted/disabled) are marked reconciled with
  # no mint. The local `invitation_code` is NEVER rewritten — only FOAF gains
  # the matching reservation.
  #
  # DRY_RUN (default 'true'): prints every action and writes NOTHING. Always run
  # dry-run first, review the output, THEN re-run with DRY_RUN=false.
  #
  #   DRY_RUN=true  rails backfill:invitation_issuance_to_foaf   # preview
  #   DRY_RUN=false rails backfill:invitation_issuance_to_foaf   # live
  #
  # Idempotent: a clean re-run reports 0 candidates. Gated by
  # FOAF_AUTH_INVITE_BRIDGE_ENABLED (off => no-op, no FOAF calls).
  desc "Backfill existing local invitation issuance metadata into FOAF (Job 51 Phase 2). DRY_RUN=true (default) writes nothing."
  task invitation_issuance_to_foaf: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'true'))
    summary = InvitationIssuanceBackfill.run(dry_run: dry_run)
    puts "backfill:invitation_issuance_to_foaf #{dry_run ? '[DRY-RUN]' : '[LIVE]'}: #{summary.inspect}"
  end
end
