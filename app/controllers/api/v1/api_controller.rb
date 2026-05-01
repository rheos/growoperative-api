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
      Rails.logger.debug("Decoded JWT: #{decoded.inspect}")

      if decoded['jti'] && JWTBlacklist.exists?(jti: decoded['jti'])
        clear_jwt_cookie! if cookie_jwt
        return
      end

      # Handle nested user_id structure
      user_id = decoded['sub']
      if user_id.is_a?(Hash)
        user_id = user_id['user_id']
        user_id = user_id['user_id'] if user_id.is_a?(Hash)
      end

      Rails.logger.debug("Extracted user_id: #{user_id.inspect}")

      user = User.find_by(id: user_id)
      # Stale cookie pointing at a user that no longer exists (e.g. after a
      # demo DB reset). Kill it so the next request arrives clean rather than
      # producing a confusing dashboard-flash-then-401 loop on the client.
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

    token = JwtGenerationService.new(user_id: user.id).token
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
      cookies.signed[:jwt] = {
        value: token,
        expires: time,
        httponly: true,
        domain: ENV.fetch('COOKIE_DOMAIN', '.growoperative.app'),
        same_site: :none,
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

  private

  def authenticate!
    unauthorized! unless current_user
  end

  def unauthorized!
    head(:unauthorized)
  end
end
