require 'digest'

class JwtGenerationService
  SIGNING_ALGORITHM = 'HS256'

  class JWTGenerationError < StandardError; end

  def initialize(user_id)
    @user_id = user_id
  end

  def token
    raise JWTGenerationError, "User ID is required" if @user_id.nil?
    
    begin
    JWT.encode(payload, secret, SIGNING_ALGORITHM)
    rescue JWT::EncodeError => e
      Rails.logger.error("JWT Generation Error: #{e.message}")
      raise JWTGenerationError, "Failed to generate JWT token: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("Unexpected error during JWT generation: #{e.message}")
      raise JWTGenerationError, "Unexpected error during JWT generation: #{e.message}"
    end
  end

  private

  def payload
    @payload ||= { iat: Time.now.to_i, sub: @user_id }
  end

  def secret
    secret_key = ENV['SECRET_KEY_BASE']
    if secret_key.nil? || secret_key.empty?
      Rails.logger.error("SECRET_KEY_BASE environment variable is not set")
      raise JWTGenerationError, "JWT secret key is not configured"
    end
    secret_key
  end
end
