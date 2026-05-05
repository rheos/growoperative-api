class JwtDecodingService
  SIGNING_ALGORITHM = 'HS256'
  AUTH_SIGNING_ALGORITHM = 'RS256'
  DEFAULT_AUDIENCE = 'growoperative'.freeze
  AUTH_ISSUER = 'auth.foaf.io'.freeze
  CLOCK_SKEW = 30

  class JWTDecodingError < StandardError; end

  def initialize(token, audience: nil)
    @token = token
    @audience = audience || ENV.fetch('FOAF_AUD', DEFAULT_AUDIENCE)
  end

  def decrypt!
    raise JWTDecodingError, "Token is required" if @token.nil? || @token.empty?

    begin
      header = JWT.decode(@token, nil, false).last
      return decrypt_auth_token!(header) if header['alg'] == AUTH_SIGNING_ALGORITHM

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

  def decrypt_auth_token!(header)
    kid = header['kid'].to_s
    snapshot = AuthRevocationSnapshot.current(audience: @audience, request_id: CurrentRequestId.value)
    if snapshot&.revoked_kid?(kid)
      Rails.logger.warn("JWT rejected: kid=#{kid.inspect} revoked request_id=#{CurrentRequestId.value}")
      raise JWTDecodingError, "JWT signing key has been revoked"
    end

    key = AuthJwksClient.public_key_for(kid, request_id: CurrentRequestId.value)
    decoded = JWT.decode(
      @token,
      key,
      true,
      algorithm: AUTH_SIGNING_ALGORITHM,
      iss: AUTH_ISSUER,
      verify_iss: true,
      aud: @audience,
      verify_aud: true,
      leeway: CLOCK_SKEW
    ).first

    enforce_revocation_snapshot!(decoded, snapshot)
    decoded
  rescue AuthJwksClient::Error, AuthRevocationSnapshot::Error => e
    Rails.logger.warn("JWT auth.foaf.io verification failed request_id=#{CurrentRequestId.value}: #{e.message}")
    raise JWTDecodingError, e.message
  end

  def enforce_revocation_snapshot!(decoded, snapshot)
    return unless snapshot

    sub = decoded['sub'].to_s
    cutoff = snapshot.cutoff_for(sub)
    if cutoff && decoded['iat'].to_i > 0 && decoded['iat'].to_i < cutoff.to_i
      Rails.logger.warn("JWT rejected: sub cutoff reached request_id=#{CurrentRequestId.value}")
      raise JWTDecodingError, "JWT was issued before the identity cutoff"
    end

    if snapshot.revoked_jti?(decoded['jti'].to_s)
      Rails.logger.warn("JWT rejected: jti revoked request_id=#{CurrentRequestId.value}")
      raise JWTDecodingError, "JWT has been revoked"
    end
  end

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
