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
    jwt = cookies.signed[:jwt]
    return unless jwt

    begin
      decoded = JwtDecodingService.new(jwt).decrypt!
      
      # Debug logging
      Rails.logger.debug("Decoded JWT: #{decoded.inspect}")
      
      # Check if token is blacklisted
      return if decoded['jti'] && JWTBlacklist.exists?(jti: decoded['jti'])
      
      # Handle nested user_id structure
      user_id = decoded['sub']
      if user_id.is_a?(Hash)
        user_id = user_id['user_id']
        # Handle double nesting if it exists
        user_id = user_id['user_id'] if user_id.is_a?(Hash)
      end
      
      Rails.logger.debug("Extracted user_id: #{user_id.inspect}")
      
      @current_user ||= User.find_by(id: user_id)
    rescue JwtDecodingService::JWTDecodingError => e
      Rails.logger.error("JWT Decoding Error: #{e.message}")
      return nil
    end
  end

  def assign_jwt_cookies(user)
    return unless user

    token = JwtGenerationService.new(user_id: user.id).token
    time = 1.year.from_now
    
    # For development with IP addresses, we need different cookie settings
    if Rails.env.development?
      cookies.signed[:jwt] = {
        value: token,
        expires: time,
        httponly: true,
        same_site: :lax,
        secure: false  # Allow HTTP for development
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

  private

  def authenticate!
    unauthorized! unless current_user
  end

  def unauthorized!
    head(:unauthorized)
  end
end
