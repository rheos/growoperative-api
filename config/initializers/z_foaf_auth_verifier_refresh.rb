if Rails.env.production? && ENV.fetch('FOAF_AUTH_VERIFIER_REFRESH_ENABLED', 'true') == 'true'
  Rails.application.config.after_initialize do
    audience = ENV.fetch('FOAF_AUD', JwtDecodingService::DEFAULT_AUDIENCE)

    begin
      if JwtDecodingService.shared_auth_verifier?
        FoafAuthVerifier.refresh!
      else
        AuthJwksClient.refresh!
        AuthRevocationSnapshot.refresh!(audience: audience)
      end
    rescue StandardError => e
      Rails.logger.warn("[foaf-auth-verifier] initial refresh failed: #{e.class}: #{e.message}")
    end

    Thread.new do
      Thread.current.name = 'foaf-auth-verifier-refresh' if Thread.current.respond_to?(:name=)
      loop do
        sleep 5.minutes
        begin
          if JwtDecodingService.shared_auth_verifier?
            FoafAuthVerifier.refresh!
          else
            AuthJwksClient.refresh!
            AuthRevocationSnapshot.refresh!(audience: audience)
          end
        rescue StandardError => e
          Rails.logger.warn("[foaf-auth-verifier] background refresh failed: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
