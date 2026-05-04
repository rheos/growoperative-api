class JwtDecodingService
  SIGNING_ALGORITHM = 'HS256'
  DEFAULT_AUDIENCE = 'growoperative'.freeze

  class JWTDecodingError < StandardError; end

  def initialize(token, audience: nil)
    @token = token
    @audience = audience || ENV.fetch('FOAF_AUD', DEFAULT_AUDIENCE)
  end

  def decrypt!
    raise JWTDecodingError, "Token is required" if @token.nil? || @token.empty?

    begin
      decoded = JWT.decode(@token, secret, true, { algorithm: SIGNING_ALGORITHM }).first
      enforce_audience!(decoded)
      decoded
    rescue JWT::DecodeError => e
      Rails.logger.error("JWT Decode Error: #{e.message}")
      raise JWTDecodingError, "Failed to decode JWT token: #{e.message}"
    rescue JWT::ExpiredSignature => e
      Rails.logger.error("JWT Expired: #{e.message}")
      raise JWTDecodingError, "JWT token has expired"
    rescue JWT::VerificationError => e
      Rails.logger.error("JWT Verification Error: #{e.message}")
      raise JWTDecodingError, "JWT token verification failed: #{e.message}"
    rescue JWTDecodingError
      raise
    rescue StandardError => e
      Rails.logger.error("Unexpected error during JWT decoding: #{e.message}")
      raise JWTDecodingError, "Unexpected error during JWT decoding: #{e.message}"
    end
  end

  private

  # Master plan §12 (Audience Enforcement) + §JWT Contract:
  # "Each app backend rejects tokens whose `aud` does not exactly match
  # its own configured audience."
  #
  # Bridge nuance: legacy HS256 tokens issued before Job 09 carry no
  # `aud` claim and a hash-shaped `sub`. Those still need to authenticate
  # through the time-boxed Rails shim (master plan §JWT Contract → Bridge
  # token contract). So enforce `aud` only on v1 tokens — i.e. when
  # `sub` is a plain string. Tokens that already declare an audience
  # but for the wrong app are always rejected.
  def enforce_audience!(decoded)
    sub = decoded['sub']
    aud = decoded['aud']
    v1_token = sub.is_a?(String) && !sub.empty?

    if aud.present? && aud != @audience
      Rails.logger.warn("JWT rejected: aud=#{aud.inspect} expected=#{@audience.inspect}")
      raise JWTDecodingError, "JWT audience does not match this app"
    end

    if v1_token && aud.blank?
      Rails.logger.warn("JWT rejected: v1 sub present but no aud claim")
      raise JWTDecodingError, "JWT audience claim is required"
    end
  end

  def secret
    secret_key = ENV['SECRET_KEY_BASE']
    if secret_key.nil? || secret_key.empty?
      Rails.logger.error("SECRET_KEY_BASE environment variable is not set")
      raise JWTDecodingError, "JWT secret key is not configured"
    end
    secret_key
  end
end
