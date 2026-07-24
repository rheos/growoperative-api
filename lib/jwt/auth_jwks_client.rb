require 'json'
require 'jwt'
require 'net/http'
require 'openssl'
require 'uri'

class AuthJwksClient
  JWKS_TTL = 1.hour
  LAST_GOOD_MAX_AGE = 24.hours
  NEGATIVE_CACHE_TTL = 30.seconds
  DEFAULT_JWKS_URL = 'https://auth.foaf.io/.well-known/jwks.json'.freeze

  class Error < StandardError; end
  class UnknownKidError < Error; end
  class FetchError < Error; end

  class << self
    attr_writer :http_get

    def public_key_for(kid, now: Time.current, request_id: nil)
      raise UnknownKidError, 'kid is required' if kid.blank?
      raise UnknownKidError, "kid #{kid.inspect} is negative-cached" if negative_cached?(kid, now: now)

      entry = key_cache[kid]
      return entry[:public_key] if entry && fresh?(entry, now: now)

      refresh!(now: now, request_id: request_id)
      entry = key_cache[kid]
      return entry[:public_key] if entry

      negative_cache[kid] = now + NEGATIVE_CACHE_TTL
      raise UnknownKidError, "kid #{kid.inspect} is unknown"
    rescue FetchError
      entry = key_cache[kid]
      if entry && now - entry[:fetched_at] <= LAST_GOOD_MAX_AGE
        Rails.logger.warn("[AuthJwksClient] request_id=#{request_id} using last-good JWKS for kid=#{kid}")
        return entry[:public_key]
      end
      raise
    end

    def refresh!(now: Time.current, request_id: nil)
      mutex.synchronize do
        payload = fetch_payload(request_id: request_id)
        keys = payload.fetch('keys')
        raise FetchError, 'JWKS keys must be an array' unless keys.is_a?(Array)

        @key_cache = keys.each_with_object({}) do |jwk, acc|
          kid = jwk['kid'].to_s
          next if kid.blank?
          acc[kid] = {
            jwk: jwk,
            public_key: public_key_from_jwk(jwk),
            fetched_at: now
          }
        end
        @last_success_at = now
        @negative_cache = {}
        @key_cache
      end
    rescue KeyError, JSON::ParserError, JWT::JWKError, OpenSSL::PKey::RSAError, ArgumentError => e
      raise FetchError, e.message
    end

    def reset!
      @key_cache = {}
      @negative_cache = {}
      @last_success_at = nil
      @http_get = nil
    end

    private

    def key_cache
      @key_cache ||= {}
    end

    def negative_cache
      @negative_cache ||= {}
    end

    def mutex
      @mutex ||= Mutex.new
    end

    def fresh?(entry, now:)
      now - entry[:fetched_at] < JWKS_TTL
    end

    def negative_cached?(kid, now:)
      expires_at = negative_cache[kid]
      return false unless expires_at
      return true if expires_at > now
      negative_cache.delete(kid)
      false
    end

    def fetch_payload(request_id:)
      body = if @http_get
        @http_get.call(jwks_url, request_headers(request_id))
      else
        net_http_get(jwks_url, request_headers(request_id))
      end
      JSON.parse(body)
    rescue StandardError => e
      raise FetchError, e.message
    end

    def jwks_url
      ENV.fetch('FOAF_AUTH_JWKS_URL', DEFAULT_JWKS_URL)
    end

    def request_headers(request_id)
      headers = { 'Accept' => 'application/json' }
      headers['X-Request-ID'] = request_id if request_id.present?
      headers
    end

    def net_http_get(url, headers)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri.request_uri, headers)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 2
      http.read_timeout = 3
      response = http.request(request)
      raise FetchError, "JWKS fetch failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end

    def public_key_from_jwk(jwk)
      JWT::JWK.import(jwk).public_key
    end
  end
end
