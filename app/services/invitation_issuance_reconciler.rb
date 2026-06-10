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
# Per-row outcome (mirrors the dual-write contract):
#   * 201 -> store `auth_invitation_id`, set state `reconciled`.
#   * 409 code_taken (the string is active in FOAF under a different row)
#     -> set state `failed`, log the conflict.
#   * any other non-201 / FOAF error -> leave `unsynced` for the next run.
#
# Redemption stays LOCAL this phase: the local `invitation_code` is the
# redemption key and is intentionally NOT overwritten. The FOAF row created
# here is the issuance-authority record, not the redeemable code.
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

    status, body = AuthFoafClient.create_invitation(
      inviter_foaf_id: inviter_foaf_id,
      target_app: 'growoperative',
      generator: invitation.code_strategy.presence || 'pronounceable',
      multi_use: invitation.multi_use,
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
      # The string is active in FOAF under a different row — a hard conflict
      # the sweep can't resolve. Mark failed so it stops being retried and
      # surfaces for operator review.
      @logger.warn("InvitationIssuanceReconciler: invitation=#{invitation.id} code_taken in FOAF (status=409 body=#{body.inspect}); marking failed")
      invitation.update!(foaf_invitation_state: Invitation::FOAF_STATE_FAILED)
      summary[:failed] += 1
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

  def bridge_on?
    ActiveModel::Type::Boolean.new.cast(ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'])
  end
end
