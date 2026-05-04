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
    # Try cookie first, fall back to Authorization Bearer header
    cookie_jwt = cookies.signed[:jwt]
    header_jwt = request.headers['Authorization']&.sub(/^Bearer\s+/, '')
    jwt = cookie_jwt || header_jwt
    return unless jwt

    begin
      decoded = JwtDecodingService.new(jwt).decrypt!
      # NOTE: never log `decoded` here — claims contain user_name and
      # may contain email. Use jti / sub fingerprints in incident
      # forensics instead.

      if decoded['jti'] && JWTBlacklist.exists?(jti: decoded['jti'])
        clear_jwt_cookie! if cookie_jwt
        return
      end

      user = resolve_user_from_jwt(decoded)
      # Stale cookie pointing at a user that no longer exists (e.g. after a
      # demo DB reset, or an unresolvable v1 sub during the bridge). Kill it
      # so the next request arrives clean rather than producing a confusing
      # dashboard-flash-then-401 loop on the client.
      if user.nil? && cookie_jwt
        clear_jwt_cookie!
        return
      end

      @current_user ||= user
    rescue JwtDecodingService::JWTDecodingError => e
      Rails.logger.error("JWT Decoding Error: #{e.message}")
      clear_jwt_cookie! if cookie_jwt
      nil
    end
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

  private

  def authenticate!
    unauthorized! unless current_user
  end

  def unauthorized!
    head(:unauthorized)
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
end
