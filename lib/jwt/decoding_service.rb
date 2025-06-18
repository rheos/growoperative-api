class JwtDecodingService
  SIGNING_ALGORITHM = 'HS256'

  class JWTDecodingError < StandardError; end

  def initialize(token)
    @token = token
  end

  def decrypt!
    raise JWTDecodingError, "Token is required" if @token.nil? || @token.empty?

    begin
      JWT.decode(@token, secret, true, { algorithm: SIGNING_ALGORITHM }).first
    rescue JWT::DecodeError => e
      Rails.logger.error("JWT Decode Error: #{e.message}")
      raise JWTDecodingError, "Failed to decode JWT token: #{e.message}"
    rescue JWT::ExpiredSignature => e
      Rails.logger.error("JWT Expired: #{e.message}")
      raise JWTDecodingError, "JWT token has expired"
    rescue JWT::VerificationError => e
      Rails.logger.error("JWT Verification Error: #{e.message}")
      raise JWTDecodingError, "JWT token verification failed: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("Unexpected error during JWT decoding: #{e.message}")
      raise JWTDecodingError, "Unexpected error during JWT decoding: #{e.message}"
    end
  end

  private

  def secret
    secret_key = ENV['SECRET_KEY_BASE']
    if secret_key.nil? || secret_key.empty?
      Rails.logger.error("SECRET_KEY_BASE environment variable is not set")
      raise JWTDecodingError, "JWT secret key is not configured"
    end
    secret_key
  end
end
