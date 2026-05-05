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

    if decoded['jti'] && JWTBlacklist.exists?(jti: decoded['jti'])
      clear_jwt_cookie! if current_jwt_from_cookie?
      return @current_user = nil
    end

    user = resolve_user_from_jwt(decoded)
    if user&.auth_inactive?
      clear_jwt_cookie! if current_jwt_from_cookie?
      return @current_user = nil
    end

    # Stale cookie pointing at a user that no longer exists (e.g. after a
    # demo DB reset, or an unresolvable v1 sub during the bridge). Kill it
    # so the next request arrives clean rather than producing a confusing
    # dashboard-flash-then-401 loop on the client.
    if user.nil? && current_jwt_from_cookie?
      clear_jwt_cookie!
    end

    @current_user = user
  end

  def assign_jwt_cookies(user)
    return unless user

    # Defensive: explicitly delete first so any pre-existing cookie at the
    # configured domain is cleared before we write the new one. Without this,
    # a cookie left over from a different deployment with a different path or
    # SameSite attribute could coexist alongside the new one and cause auth
    # to flap depending on which the browser sends first.
    clear_jwt_cookie!

    token = JwtGenerationService.new(user).token
    time = 1.year.from_now

    # Dev: Lax is sufficient because localhost ports are same-site.
    # None+Secure=false is rejected by modern browsers.
    if Rails.env.development?
      cookies.signed[:jwt] = {
        value: token,
        expires: time,
        httponly: true,
        same_site: :lax,
        secure: false
      }
    else
      # SameSite=Lax: blocks cross-site state-changing requests (CSRF defense).
      # All current frontends (growoperative.app, app/demo/beta.growoperative.app)
      # share the registrable domain growoperative.app, so Lax permits the
      # legitimate same-site flow. See foaf-auth/docs/audits/csrf-coverage-audit.md.
      cookies.signed[:jwt] = {
        value: token,
        expires: time,
        httponly: true,
        domain: ENV.fetch('COOKIE_DOMAIN', '.growoperative.app'),
        same_site: :lax,
        secure: true
      }
    end
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
      avatar_url: user.avatar_url,
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

    unauthorized!
  end

  def unauthorized!
    head(:unauthorized)
  end

  def current_jwt_payload
    return @current_jwt_payload if defined?(@current_jwt_payload)

    jwt, source = current_jwt_token_and_source
    @current_jwt_source = source
    return @current_jwt_payload = nil unless jwt

    @current_jwt_payload = CurrentRequestId.with(request.request_id) do
      JwtDecodingService.new(jwt).decrypt!
    end
    # NOTE: never log decoded claims here — they contain user_name and
    # may contain email. Use jti / sub fingerprints in incident forensics.
  rescue JwtDecodingService::JWTDecodingError => e
    Rails.logger.error("JWT Decoding Error: #{e.message}")
    clear_jwt_cookie! if current_jwt_from_cookie?
    @current_jwt_payload = nil
  end

  def current_jwt_foaf_id
    sub = current_jwt_payload && current_jwt_payload['sub']
    sub if sub.is_a?(String) && sub.present?
  end

  def ensure_local_user_for_current_identity!
    return current_user if current_user
    return unless profileless_onboarding_request?

    foaf_id = current_jwt_foaf_id
    return if foaf_id.blank?

    User.find_or_create_by!(foaf_id: foaf_id) do |user|
      user.user_name = unique_local_handle_for(current_jwt_payload['user_name'], foaf_id)
      email = current_jwt_payload['email'].to_s.downcase.presence
      user.email = email if email && !User.where.not(foaf_id: foaf_id).exists?(email: email)
      user.first_name = current_jwt_payload['first_name'].presence
      user.last_name = current_jwt_payload['last_name'].presence
      user.display_name = current_jwt_payload['display_name'].presence || user.user_name
      user.name = [user.first_name, user.last_name].compact.join(' ').presence || user.display_name
      password = SecureRandom.hex(32)
      user.password = password
      user.password_confirmation = password
    end.tap { |user| @current_user = user unless user.auth_inactive? }
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

  def current_jwt_token_and_source
    header_jwt = request.headers['Authorization']&.sub(/^Bearer\s+/, '')
    return [header_jwt, :header] if header_jwt.present?

    cookie_jwt = cookies.signed[:jwt]
    return [cookie_jwt, :cookie] if cookie_jwt.present?

    [nil, nil]
  end

  def current_jwt_from_cookie?
    @current_jwt_source == :cookie
  end

  def profileless_onboarding_request?
    controller_path == 'api/v1/onboarding' && %w[create status].include?(action_name)
  end

  def unique_local_handle_for(preferred, foaf_id)
    base = preferred.to_s.downcase.gsub(/[^a-z0-9_.-]/, '').presence || "user-#{foaf_id.delete('-')[0, 8]}"
    base = base[0, 32]
    return base unless User.where.not(foaf_id: foaf_id).exists?(user_name: base)

    suffix = foaf_id.delete('-')[0, 8]
    "#{base[0, 23]}-#{suffix}"
  end

  def growoperative_role_for(labels)
    primary = (labels - %w[demo]).first || 'consumer'
    %w[admin superuser].include?(primary) ? 'broker' : primary
  end
end
