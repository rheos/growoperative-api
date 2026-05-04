require 'digest'

class JwtGenerationService
  SIGNING_ALGORITHM = 'HS256'
  DEFAULT_AUDIENCE = 'growoperative'.freeze
  DEFAULT_TOKEN_LIFETIME = 1.year

  class JWTGenerationError < StandardError; end

  # Phase-2 v1 token claims (master plan §JWT Contract):
  #   sub        = user.foaf_id
  #   aud        = registered app slug (defaults to ENV FOAF_AUD or "growoperative")
  #   legacy_uid = old numeric users.id, fallback metadata for the bridge window only
  #   iat / exp / jti / user_name / optional email
  #
  # `iss = "auth.foaf.io"` is intentionally absent until the Phase-3 cutover
  # (Job 16 ships RS256 + JWKS); until then no `iss` claim is emitted.
  def initialize(user, aud: nil)
    @user = user
    @aud = aud || ENV.fetch('FOAF_AUD', DEFAULT_AUDIENCE)
  end

  def token
    raise JWTGenerationError, "User is required" if @user.nil?
    raise JWTGenerationError, "User foaf_id is missing" if @user.foaf_id.blank?

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
    @payload ||= begin
      claims = {
        iat: Time.now.to_i,
        exp: DEFAULT_TOKEN_LIFETIME.from_now.to_i,
        sub: @user.foaf_id,
        aud: @aud,
        jti: SecureRandom.uuid,
        legacy_uid: @user.id,
        user_name: @user.user_name,
      }
      claims[:email] = @user.email if @user.email.present?
      claims
    end
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
