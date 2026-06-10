# Job 51 Phase 2 — backfill existing local invitation issuance metadata into
# FOAF (auth.foaf.io), idempotent, dry-run by default.
#
# This runs AFTER the dual-write (Steps 06-08) has soaked. It walks every local
# `Invitation` that never reached FOAF (`auth_invitation_id` nil AND
# `foaf_invitation_state != 'reconciled'`) and brings issuance authority into
# line, WITHOUT ever touching the local redemption path. The thin rake wrapper
# is `lib/tasks/backfill_invitation_issuance_to_foaf.rake`.
#
# WHAT GETS A FOAF ROW:
#   * LIVE PENDING rows only (status pending + not disabled). These are the
#     redeemability-critical case: a real person may still type this code, so
#     FOAF must reserve the SAME string. We register the existing local string
#     via `generator: 'custom', custom_code: <code>.downcase, multi_use: true`
#     (the confirmed migration exception — `multi_use` is an ISSUANCE-only flag
#     in FOAF; redemption stays LOCAL and single-use codes stay single-use).
#   * TERMINAL rows (accepted, or disabled/revoked) get NO FOAF mint — a used
#     or switched-off code is not redeemable, so there is nothing to reserve.
#     We simply mark them `reconciled`; string reuse for terminal codes is
#     FOAF's concern post-cutover.
#
# We NEVER rewrite the local `invitation_code`. It is the redemption key; only
# FOAF gains the matching reservation (the mirror).
#
# PER-PENDING-ROW OUTCOME:
#   * availability false (FOAF already holds the string) -> `reconciled`, no
#     mint.
#   * availability true, OR the availability lookup raises -> mint the same-code
#     custom seed.
#       - 201 -> store auth_invitation_id + code_strategy, set `reconciled`.
#       - 409 code_taken / other non-201 -> set `failed`, log (NOT reconciled).
#
# IDEMPOTENT: `reconciled` rows are excluded from the candidate set, so a
# re-run finds 0 rows. `failed` rows stay in the set so a later run retries.
#
# DRY_RUN (default true): prints every action and writes NOTHING — no DB
# updates and no mutating FOAF calls (availability lookups are read-only and
# are still made so the dry-run preview is accurate).
#
# Gated by FOAF_AUTH_INVITE_BRIDGE_ENABLED (off => no-op, no FOAF calls).
class InvitationIssuanceBackfill
  DEFAULT_EXPIRES_IN_SECONDS = 7.days.to_i

  def self.run(**opts)
    new(**opts).run
  end

  def initialize(dry_run: true, expires_in_seconds: DEFAULT_EXPIRES_IN_SECONDS, logger: Rails.logger)
    @dry_run = dry_run
    @expires_in_seconds = expires_in_seconds
    @logger = logger
  end

  def run
    summary = { candidates: 0, reconciled_pending: 0, reconciled_already_present: 0,
                reconciled_terminal: 0, failed: 0, skipped_no_foaf: 0 }

    unless bridge_on?
      log('FOAF_AUTH_INVITE_BRIDGE_ENABLED off; nothing to do (no FOAF calls).')
      return summary.merge(skipped_reason: 'bridge_off')
    end

    candidates.find_each do |invitation|
      summary[:candidates] += 1
      process_one(invitation, summary)
    end

    log("done: #{summary.inspect}")
    log('0 rows to backfill (idempotent: already reconciled).') if summary[:candidates].zero?
    summary
  end

  # Candidate set: never reached FOAF and not already reconciled. `failed` rows
  # stay in the set so a re-run retries them; `reconciled` rows are the
  # idempotency boundary and are excluded, so a clean re-run finds 0.
  def candidates
    Invitation
      .where(auth_invitation_id: nil)
      .where.not(foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED)
      .order(:created_at)
  end

  private

  def process_one(invitation, summary)
    code = invitation.invitation_code.to_s
    strategy = code_strategy_for(code)

    # TERMINAL rows (accepted, or disabled/revoked): a used or switched-off code
    # is not redeemable, so FOAF needs no active row for it. Mark reconciled and
    # move on — never mint an active FOAF row for a dead code.
    if terminal?(invitation)
      log("invitation=#{invitation.id} terminal (#{terminal_reason(invitation)}); marking reconciled, no FOAF mint")
      invitation.update!(foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED) unless @dry_run
      summary[:reconciled_terminal] += 1
      return
    end

    inviter_foaf_id = invitation.user&.foaf_id
    if inviter_foaf_id.blank?
      # Can't mint against an inviter with no FOAF identity. Leave the row as-is
      # for a future run once the inviter is linked.
      log("invitation=#{invitation.id} inviter has no foaf_id; skipping (left for a later run)")
      summary[:skipped_no_foaf] += 1
      return
    end

    canonical_code = code.downcase

    # Availability pre-check. `false` => FOAF already holds the string (a prior
    # backfill run or a dual-write row) => reconciled WITHOUT a mint. A lookup
    # error => proceed to mint (the availability endpoint is advisory; the mint
    # itself is the real arbiter via 409).
    available = availability(canonical_code, invitation)

    if available == false
      log("invitation=#{invitation.id} code=#{canonical_code} already present in FOAF (availability=false); marking reconciled, no mint")
      invitation.update!(foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED) unless @dry_run
      summary[:reconciled_already_present] += 1
      return
    end

    # SAME-CODE custom seed: register the EXISTING live local string in FOAF.
    # custom_code is the live redeemable string (downcased); multi_use: true is
    # the confirmed issuance-only migration exception. The local invitation_code
    # is NEVER rewritten — only FOAF gains the matching reservation.
    log("invitation=#{invitation.id} pending; minting same-code custom seed code=#{canonical_code} strategy=#{strategy} multi_use=true")
    if @dry_run
      summary[:reconciled_pending] += 1
      return
    end

    status, body = AuthFoafClient.create_invitation(
      inviter_foaf_id: inviter_foaf_id,
      target_app: 'growoperative',
      generator: 'custom',
      custom_code: canonical_code,
      multi_use: true,
      expires_in_seconds: @expires_in_seconds
    )

    if status == 201 && body.is_a?(Hash) && body['invitation_id'].present?
      invitation.update!(
        auth_invitation_id: body['invitation_id'],
        code_strategy: body['code_strategy'].presence || strategy,
        foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED
      )
      log("invitation=#{invitation.id} minted -> auth_invitation_id=#{body['invitation_id']}; reconciled")
      summary[:reconciled_pending] += 1
    elsif status == 409
      log("invitation=#{invitation.id} code_taken in FOAF (409 body=#{body.inspect}); marking failed")
      invitation.update!(foaf_invitation_state: Invitation::FOAF_STATE_FAILED)
      summary[:failed] += 1
    else
      log("invitation=#{invitation.id} FOAF mint returned status=#{status}; marking failed")
      invitation.update!(foaf_invitation_state: Invitation::FOAF_STATE_FAILED)
      summary[:failed] += 1
    end
  rescue StandardError => e
    # FOAF unreachable mid-row: leave the row untouched so a later run retries,
    # and keep the sweep going.
    log("invitation=#{invitation.id} backfill failed (#{e.class}: #{e.message}); left for a later run")
    summary[:failed] += 1
  end

  # A row is terminal when it can no longer be redeemed: single-use accepted, or
  # switched off (disabled_at present, i.e. revoked). Live PENDING = not these.
  def terminal?(invitation)
    invitation.accepted? || invitation.disabled_at.present?
  end

  def terminal_reason(invitation)
    return 'accepted' if invitation.accepted?
    return 'disabled' if invitation.disabled_at.present?
    'unknown'
  end

  # Legacy CVCV-CVCV pronounceable codes are alpha-only; the local random
  # fallback (and any post-Step-07 hex-shaped fallback) carries digits. Tag the
  # strategy so the FOAF row records which family the seeded string came from.
  def code_strategy_for(code)
    code.to_s.match?(/\d/) ? 'hexstring' : 'pronounceable'
  end

  # Advisory availability lookup. Returns true/false, or nil if the lookup
  # raised (caller treats nil as "proceed to mint").
  def availability(canonical_code, invitation)
    AuthFoafClient.invitation_code_available?(code: canonical_code, target_app: 'growoperative')
  rescue StandardError => e
    log("invitation=#{invitation.id} availability lookup raised (#{e.class}: #{e.message}); proceeding to mint")
    nil
  end

  def log(msg)
    @logger.info("InvitationIssuanceBackfill #{@dry_run ? '[DRY-RUN]' : '[LIVE]'} #{msg}")
  end

  def bridge_on?
    ActiveModel::Type::Boolean.new.cast(ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'])
  end
end
