# Shared RS256 verifier adapter. The legacy HS256 bridge remains in
# JwtDecodingService until its independent sunset; only auth.foaf.io RS256
# tokens pass through this package-backed path.
class FoafAuthVerifier
  DEFAULT_JWKS_URL = 'https://auth.foaf.io/.well-known/jwks.json'.freeze
  DEFAULT_REVOCATIONS_URL = 'https://auth.foaf.io/v1/revocations/snapshot'.freeze

  class << self
    attr_writer :instance

    def verify(token, request_id: nil)
      instance.verify(token, request_id: request_id)
    end

    def refresh!(request_id: nil)
      instance.refresh!(request_id: request_id)
    end

    def reset!
      @instance = nil
    end

    private

    def instance
      @instance ||= Foaf::Auth::Verifier.new(
        jwks_url: ENV.fetch('FOAF_AUTH_JWKS_URL', DEFAULT_JWKS_URL),
        issuer: ENV.fetch('FOAF_AUTH_ISSUER', 'auth.foaf.io'),
        audience: ENV.fetch('FOAF_AUD', 'growoperative'),
        revocations_url: ENV.fetch(
          'FOAF_AUTH_REVOCATION_SNAPSHOT_URL',
          DEFAULT_REVOCATIONS_URL
        ),
        service_token: ENV['FOAF_AUTH_SERVICE_TOKEN'],
        jwks_ttl: 1.hour,
        revocations_ttl: 5.minutes,
        last_good_jwks_age: 24.hours,
        negative_kid_ttl: 30.seconds,
        stale_revocations_after: 15.minutes,
        clock_skew: JwtDecodingService::CLOCK_SKEW,
        logger: Rails.logger
      )
    end
  end
end
