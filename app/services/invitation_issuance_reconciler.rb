# Job 51 Phase 1 — idempotent forward-reconcile of `unsynced` invitation
# issuance rows into FOAF (auth.foaf.io).
#
# When the dual-write in `UsersController#generate_invitation` cannot reach
# FOAF on the auto-generator path, it keeps the local fallback `invitation_code`
# and tags the row `foaf_invitation_state = 'unsynced'` with a nil
# `auth_invitation_id`. This sweep finds those rows and pushes each into FOAF so
# issuance authority is consistent (spec Decision 11: a local-only fallback row
# is reconciled forward, never a competing truth).
#
# SAME-CODE SEEDING (Step 2.5 hardening): an `unsynced` fallback row already
# holds a LIVE local `invitation_code` (the redemption key). The reconciler
# registers THAT EXACT string in FOAF via `generator: 'custom',
# custom_code: <existing code>.downcase, multi_use: true` — it never mints a
# fresh/competing code. This closes the prompt-08 competing-truth hole: FOAF's
# reserved string == the live local redeemable string. `multi_use: true` is the
# confirmed migration exception — it's an ISSUANCE-only flag in FOAF
# (reuse_key/availability namespace), not a redemption flag; redemption stays
# LOCAL this whole job and the local row keeps its own `multi_use`, so
# single-use codes stay single-redeemable.
#
# Per-row outcome (mirrors the backfill contract):
#   * 201 -> store `auth_invitation_id`, set state `reconciled`.
#   * 409 code_taken -> the string may already be held in FOAF (a prior
#     backfill/dual-write row). Re-check availability: if FOAF already holds it
#     -> treat as already-present, set state `reconciled`; otherwise set
#     `failed`, log the conflict.
#   * any other non-201 / FOAF error -> leave `unsynced` for the next run.
#
# Redemption stays LOCAL this phase: the local `invitation_code` is the
# redemption key and is intentionally NOT overwritten. The FOAF row created
# here is the issuance-authority record (the matching reservation), not the
# redeemable code.
#
# Idempotent: only `unsynced` rows with a nil `auth_invitation_id` are
# candidates. `synced` / `reconciled` / `failed` rows are no-ops, so a re-run
# does nothing for already-resolved rows.
#
# Gated by FOAF_AUTH_INVITE_BRIDGE_ENABLED: off => no-op (no FOAF calls).
class InvitationIssuanceReconciler
  DEFAULT_EXPIRES_IN_SECONDS = 7.days.to_i

  def self.run(**opts)
    new(**opts).run
  end

  # `expires_in_seconds` defaults to 7 days to match the FOAF issuance
  # controller's own default; callers can override for a one-off sweep.
  def initialize(expires_in_seconds: DEFAULT_EXPIRES_IN_SECONDS, logger: Rails.logger)
    @expires_in_seconds = expires_in_seconds
    @logger = logger
  end

  def run
    summary = { processed: 0, reconciled: 0, failed: 0, skipped: 0, errored: 0 }

    unless bridge_on?
      @logger.info('InvitationIssuanceReconciler: FOAF_AUTH_INVITE_BRIDGE_ENABLED off; skipping sweep')
      return summary.merge(skipped_reason: 'bridge_off')
    end

    candidates.find_each do |invitation|
      summary[:processed] += 1
      reconcile_one(invitation, summary)
    end

    @logger.info("InvitationIssuanceReconciler: #{summary.inspect}")
    summary
  end

  private

  # Only `unsynced` rows with no FOAF id are candidates. This is the
  # idempotency boundary — anything already `synced`/`reconciled`/`failed`,
  # or anything that already carries an `auth_invitation_id`, is excluded.
  def candidates
    Invitation
      .where(foaf_invitation_state: Invitation::FOAF_STATE_UNSYNCED, auth_invitation_id: nil)
      .order(:created_at)
  end

  def reconcile_one(invitation, summary)
    inviter_foaf_id = invitation.user&.foaf_id
    if inviter_foaf_id.blank?
      # Can't mint against an inviter with no FOAF identity; leave it
      # unsynced for a future run once the inviter is linked.
      @logger.warn("InvitationIssuanceReconciler: invitation=#{invitation.id} inviter has no foaf_id; leaving unsynced")
      summary[:skipped] += 1
      return
    end

    # SAME-CODE SEEDING: register the EXISTING live local string in FOAF, never
    # a fresh/competing code. `custom_code` is the row's own redeemable code
    # (downcased to FOAF's canonical form); `multi_use: true` is the issuance-
    # only migration exception that lets a custom string be seeded. The local
    # `invitation_code` is NOT rewritten — only FOAF gains the matching
    # reservation.
    status, body = AuthFoafClient.create_invitation(
      inviter_foaf_id: inviter_foaf_id,
      target_app: 'growoperative',
      generator: 'custom',
      custom_code: invitation.invitation_code.to_s.downcase,
      multi_use: true,
      expires_in_seconds: @expires_in_seconds
    )

    if status == 201 && body.is_a?(Hash) && body['invitation_id'].present?
      invitation.update!(
        auth_invitation_id: body['invitation_id'],
        # Persist the strategy FOAF actually minted with when it tells us;
        # the redeemable local code is deliberately left untouched.
        code_strategy: body['code_strategy'].presence || invitation.code_strategy,
        foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED
      )
      summary[:reconciled] += 1
    elsif status == 409
      # code_taken: the string may already be reserved in FOAF (a prior backfill
      # or dual-write row holds it). Re-check availability — if FOAF already
      # holds our exact string, that IS the reconciled end-state, so adopt it.
      # Only a string FOAF reports as still available but refuses to mint is a
      # true conflict worth surfacing for operator review.
      if foaf_already_holds?(invitation)
        @logger.info("InvitationIssuanceReconciler: invitation=#{invitation.id} code already reserved in FOAF (409 + availability=false); marking reconciled")
        invitation.update!(foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED)
        summary[:reconciled] += 1
      else
        @logger.warn("InvitationIssuanceReconciler: invitation=#{invitation.id} code_taken in FOAF (status=409 body=#{body.inspect}); marking failed")
        invitation.update!(foaf_invitation_state: Invitation::FOAF_STATE_FAILED)
        summary[:failed] += 1
      end
    else
      # Non-201 / non-409 (e.g. FOAF 5xx): leave unsynced for the next run.
      @logger.warn("InvitationIssuanceReconciler: invitation=#{invitation.id} FOAF mint returned status=#{status}; leaving unsynced")
      summary[:errored] += 1
    end
  rescue StandardError => e
    # FOAF unreachable mid-sweep: leave this row unsynced and keep going so
    # one bad row doesn't abort the whole pass.
    @logger.warn("InvitationIssuanceReconciler: invitation=#{invitation.id} FOAF mint failed (#{e.class}: #{e.message}); leaving unsynced")
    summary[:errored] += 1
  end

  # On a 409 from the same-code seed, ask FOAF whether it already holds the
  # exact string. `available: false` means the composite unique index is
  # already claimed — in a reconcile context that means FOAF has OUR string, so
  # the row is effectively reconciled. Any lookup error is treated as "not
  # confirmed present" so we don't reconcile on a guess.
  def foaf_already_holds?(invitation)
    !AuthFoafClient.invitation_code_available?(
      code: invitation.invitation_code.to_s.downcase,
      target_app: 'growoperative'
    )
  rescue StandardError => e
    @logger.warn("InvitationIssuanceReconciler: invitation=#{invitation.id} availability re-check failed (#{e.class}: #{e.message}); not treating as present")
    false
  end

  def bridge_on?
    ActiveModel::Type::Boolean.new.cast(ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'])
  end
end
