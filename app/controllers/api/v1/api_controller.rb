require_dependency 'jwt/current_request_id'

class Api::V1::ApiController < ApplicationController
  protect_from_forgery prepend: true, with: :exception

  skip_before_action :verify_authenticity_token

  before_action :authenticate!

  def render_resource(resource)
    if resource.errors.empty?
      render json: resource
    else
      validation_error(resource)
    end
  end

  def validation_error(resource)
    render json: {
      errors: [
        {
          status: '400',
          title: 'Bad Request',
          detail: resource.errors,
          code: '100'
        }
      ]
    }, status: :bad_request
  end

  def current_user
    return @current_user if defined?(@current_user)

    decoded = current_jwt_payload
    return @current_user = nil unless decoded

    return @current_user = nil if decoded['jti'] && JwtBlacklist.exists?(jti: decoded['jti'])

    user = resolve_user_from_jwt(decoded)
    if user&.auth_inactive?
      return @current_user = nil
    end

    @current_user = user
  end

  # Decoded FOAF JWT claims for the current request (string keys), or nil when
  # unauthenticated. Reuses the already-verified payload so no token is decoded
  # twice. auth.foaf.io RS256 tokens are the source of the `foaf_address` claim;
  # legacy HS256 bridge tokens carry no address and read as blank (see Task B).
  def current_foaf_claims
    current_jwt_payload
  end

  # Single read/display resolver for the current user's own FOAF ledger address
  # (Phase 5, one-address-per-identity, Prompt 7). Reads-first / shadow-only:
  #
  #   * Behind FOAF_SHARED_READS, prefer the address carried on the verified JWT
  #     claim and shadow-diff it against users.foaf_address, logging any mismatch
  #     (Task A). Zero mismatches on demo confirms the invariant before any key
  #     move. No signing source changes and no key moves in this phase.
  #   * A token that carries no foaf_address claim while the user already has an
  #     address on file is stale (issued before the address was minted/populated).
  #     Log it (Task B). Reads are NOT blocked here; the mutation block is Phase 7.
  #   * With the flag off, behavior is unchanged: return the DB address.
  #
  # This is a shadow read only. Ledger operations still use users.foaf_address
  # until the key move lands (Prompt 9).
  def current_foaf_address
    db_address = current_user&.foaf_address
    return db_address unless Foaf::Config.shared_reads? && current_foaf_claims.present?

    claim_address = current_foaf_claims["foaf_address"] # string key (W3)

    if claim_address.blank? && db_address.present?
      Rails.logger.warn("[FOAF_SHARED_READS] stale token for foaf_id=#{current_user&.foaf_id} — no foaf_address claim")
    elsif claim_address.present? && claim_address.downcase != db_address.to_s.downcase
      Rails.logger.warn("[FOAF_SHARED_READS] address mismatch for foaf_id=#{current_user&.foaf_id}: claim=#{claim_address} db=#{db_address}")
    end

    # Reads-first/shadow-only: prefer the claim for display, but ledger
    # operations still resolve users.foaf_address until the Phase 6 key move.
    claim_address.presence || db_address
  end

  def clear_legacy_jwt_cookie!
    clear_jwt_cookie!
  end

  def clear_jwt_cookie!
    if Rails.env.development?
      cookies.delete(:jwt)
    else
      cookies.delete(:jwt, domain: ENV.fetch('COOKIE_DOMAIN', '.growoperative.app'))
    end
  end

  # FoafIdentity payload for v1 auth response envelopes (master plan §JWT
  # Contract / Phase 2). Identity-only — profile-shaped fields (roles,
  # subnet memberships, etc.) stay on the legacy `data.attributes` block
  # so the protocol/app boundary is not violated.
  def identity_payload(user)
    {
      foaf_id: user.foaf_id,
      user_name: user.user_name,
      display_name: user.display_name,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      # Identity-only email-verification fields. The local users table doesn't
      # carry these columns (Job 50 out-of-scope), so they fall back to nil
      # here; the authoritative values arrive in auth's `body['identity']` on
      # profile update + session refresh.
      email_verified_at: (user.respond_to?(:email_verified_at) ? user.email_verified_at&.iso8601 : nil),
      pending_email: (user.respond_to?(:pending_email) ? user.pending_email : nil),
      avatar_url: user.avatar_url,
      # Enriched-profile identity fields (Plan 30), mirrored locally from auth
      # (canonical there); present on the users table since the Plan 30 migration.
      about: user.about,
      area_label: user.area_label,
      # FOAF ledger address for display. Behind FOAF_SHARED_READS this resolves
      # from the JWT claim (shadow-diffed against the DB); otherwise from the DB.
      # Resolver only shadow-diffs the *current* user's own address, so fall back
      # to the passed user's DB address for any non-current-user identity payload.
      foaf_address: (user == current_user ? current_foaf_address : user.foaf_address),
      created_at: user.created_at&.iso8601,
      updated_at: user.updated_at&.iso8601,
    }
  end

  def app_profile_payload(user)
    labels = user.user_groups.map(&:group_label)
    {
      id: user.id,
      foaf_id: user.foaf_id,
      role: growoperative_role_for(labels),
      # App-owned "what I grow/sell" blurb (Plan 30). Not portable to other apps.
      offering: user.offering,
      invitation_limit: user.invite_limit,
      invite_limit: user.invite_limit,
      is_demo: labels.include?('demo'),
      is_admin: labels.include?('admin') || labels.include?('superuser'),
      is_superuser: labels.include?('superuser'),
      user_types: user.user_groups.map { |group| { id: group.id, group_label: group.group_label } },
      subnet_memberships: user.subnet_memberships.includes(:subnet).map do |membership|
        {
          id: membership.id,
          subnet_id: membership.subnet_id,
          subnet_name: membership.subnet.name,
          is_primary: membership.is_primary
        }
      end,
      app_preferences: {}
    }
  end

  private

  def authenticate!
    return if current_user
    return if profileless_onboarding_request? && current_jwt_foaf_id.present?

    if @bridge_expired_jwt
      render_bridge_expired!
    else
      unauthorized!
    end
  end

  def unauthorized!
    head(:unauthorized)
  end

  # Stale-client signal: a token was presented that we no longer accept
  # (HS256 after the bridge sunset). Tell the app to clear local auth and
  # route the user back through login. See foaf-auth/docs/plans/37-...
  def render_bridge_expired!
    render json: {
      error: 'Legacy auth bridge has been retired; please sign in again.',
      code: JwtDecodingService::BRIDGE_EXPIRED_CODE
    }, status: :unauthorized
  end

  def current_jwt_payload
    return @current_jwt_payload if defined?(@current_jwt_payload)

    jwt = current_jwt_token
    return @current_jwt_payload = nil unless jwt

    @current_jwt_payload = CurrentRequestId.with(request.request_id) do
      JwtDecodingService.new(jwt).decrypt!
    end
    # NOTE: never log decoded claims here — they contain user_name and
    # may contain email. Use jti / sub fingerprints in incident forensics.
  rescue JwtDecodingService::JWTDecodingError => e
    Rails.logger.error("JWT Decoding Error: #{e.message}")
    @bridge_expired_jwt = true if e.code == JwtDecodingService::BRIDGE_EXPIRED_CODE
    clear_legacy_jwt_cookie!
    @current_jwt_payload = nil
  end

  def current_jwt_foaf_id
    sub = current_jwt_payload && current_jwt_payload['sub']
    sub if sub.is_a?(String) && sub.present?
  end

  def ensure_local_user_for_current_identity!(initial_depth: nil, initial_group_label: nil)
    return current_user if current_user
    return unless profileless_onboarding_request?

    foaf_id = current_jwt_foaf_id
    return if foaf_id.blank?

    handle = unique_local_handle_for(current_jwt_payload['user_name'], foaf_id)
    email = current_jwt_payload['email'].to_s.downcase.presence
    email_available = email && !User.default_scoped.where.not(foaf_id: foaf_id).exists?(email: email)

    created = false
    User.find_or_create_by!(foaf_id: foaf_id) do |user|
      created = true
      user.user_name = handle
      user.email = email if email_available
      user.first_name = current_jwt_payload['first_name'].presence
      user.last_name = current_jwt_payload['last_name'].presence
      user.display_name = current_jwt_payload['display_name'].presence || user.user_name
      user.name = [user.first_name, user.last_name].compact.join(' ').presence || user.display_name
      user.depth = initial_depth unless initial_depth.nil?
      password = SecureRandom.hex(32)
      user.password = password
      user.password_confirmation = password
    end.tap do |user|
      if created && initial_group_label.present?
        user.user_groups.find_or_create_by!(group_label: initial_group_label)
      end
      @current_user = user unless user.auth_inactive?
    end
  end

  # JWT bridge resolution (master plan §JWT Contract → Bridge token contract).
  #
  # New v1 tokens carry `sub = foaf_id` (string) plus `legacy_uid` for
  # downstream code that still keys on the old numeric users.id. Legacy
  # HS256 tokens carry `sub = { user_id: { user_id: N } }` (the historical
  # double-nest) and have no `legacy_uid`.
  #
  # Verification rule: prefer foaf_id. If `sub` is a non-empty string but
  # does not resolve, return nil (the request is rejected) — never fall
  # through to `legacy_uid`, which would silently authenticate a different
  # user. Fall back to `legacy_uid` / nested `sub` ONLY when `sub` is
  # absent or non-string (legacy bridge tokens).
  def resolve_user_from_jwt(decoded)
    sub = decoded['sub']
    if sub.is_a?(String) && !sub.empty?
      return User.find_by(foaf_id: sub)
    end

    user_id = decoded['legacy_uid']
    if user_id.nil? && sub.is_a?(Hash)
      user_id = sub['user_id']
      user_id = user_id['user_id'] if user_id.is_a?(Hash)
    end
    return nil if user_id.nil?
    User.find_by(id: user_id)
  end

  def current_jwt_token
    authorization = request.headers['Authorization'].to_s
    match = authorization.match(/\ABearer\s+(.+)\z/i)
    match && match[1]
  end

  def profileless_onboarding_request?
    controller_path == 'api/v1/onboarding' && %w[create status].include?(action_name)
  end

  def unique_local_handle_for(preferred, foaf_id)
    base = preferred.to_s.downcase.gsub(/[^a-z0-9_.-]/, '').presence || "user-#{foaf_id.delete('-')[0, 8]}"
    base = base[0, 32]
    return base unless User.default_scoped.where.not(foaf_id: foaf_id).exists?(user_name: base)

    suffix = foaf_id.delete('-')[0, 8]
    "#{base[0, 23]}-#{suffix}"
  end

  def growoperative_role_for(labels)
    primary = (labels - %w[demo]).first || 'consumer'
    %w[admin superuser].include?(primary) ? 'broker' : primary
  end
end
