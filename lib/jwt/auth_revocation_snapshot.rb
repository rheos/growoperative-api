require 'json'
require 'net/http'
require 'set'
require 'uri'

class AuthRevocationSnapshot
  SNAPSHOT_TTL = 5.minutes
  STALE_ALERT_AFTER = 15.minutes
  DEFAULT_SNAPSHOT_URL = 'https://auth.foaf.io/v1/revocations/snapshot'.freeze

  class Error < StandardError; end
  class FetchError < Error; end

  class << self
    attr_writer :http_get

    def current(audience:, now: Time.current, request_id: nil)
      return @snapshot if @snapshot && @snapshot.audience == audience && fresh?(now: now)
      refresh!(audience: audience, now: now, request_id: request_id)
    rescue FetchError => e
      if @snapshot && @snapshot.audience == audience
        warn_if_stale(now: now, error: e.message, request_id: request_id)
        return @snapshot
      end
      Rails.logger.warn("[AuthRevocationSnapshot] request_id=#{request_id} no snapshot available: #{e.message}")
      nil
    end

    def refresh!(audience:, now: Time.current, request_id: nil)
      payload = fetch_payload(audience: audience, request_id: request_id)
      @snapshot = Snapshot.new(payload, fetched_at: now)
    rescue JSON::ParserError, KeyError, ArgumentError => e
      raise FetchError, e.message
    end

    def reset!
      @snapshot = nil
      @http_get = nil
    end

    private

    def fresh?(now:)
      now - @snapshot.fetched_at < SNAPSHOT_TTL
    end

    def warn_if_stale(now:, error:, request_id:)
      return unless now - @snapshot.generated_at > STALE_ALERT_AFTER
      Rails.logger.error("[AuthRevocationSnapshot] request_id=#{request_id} snapshot stale age=#{(now - @snapshot.generated_at).to_i}s error=#{error}")
    end

    def fetch_payload(audience:, request_id:)
      body = if @http_get
        @http_get.call(snapshot_url(audience), request_headers(request_id))
      else
        net_http_get(snapshot_url(audience), request_headers(request_id))
      end
      JSON.parse(body)
    rescue StandardError => e
      raise FetchError, e.message
    end

    def snapshot_url(audience)
      uri = URI.parse(ENV.fetch('FOAF_AUTH_REVOCATION_SNAPSHOT_URL', DEFAULT_SNAPSHOT_URL))
      params = URI.decode_www_form(uri.query.to_s)
      params << ['audience', audience]
      uri.query = URI.encode_www_form(params)
      uri.to_s
    end

    def request_headers(request_id)
      headers = { 'Accept' => 'application/json' }
      token = ENV['FOAF_AUTH_SERVICE_TOKEN'].to_s
      headers['Authorization'] = "Bearer #{token}" if token.present?
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
      raise FetchError, "snapshot fetch failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end
  end

  class Snapshot
    attr_reader :audience, :fetched_at, :generated_at

    def initialize(payload, fetched_at:)
      @audience = payload.fetch('audience').to_s
      @generated_at = Time.zone.parse(payload.fetch('generated_at').to_s)
      @fetched_at = fetched_at
      @revoked_kids = Set.new(Array(payload['revoked_kids']).map { |row| row['kid'].to_s }.reject(&:blank?))
      @tokens_invalid_before = (payload['tokens_invalid_before'] || {}).transform_values { |value| Time.zone.parse(value.to_s) }
      @revoked_jtis = Array(payload['revoked_jtis']).each_with_object({}) do |row, acc|
        acc[row['jti'].to_s] = Time.zone.parse(row['exp'].to_s)
      end
    end

    def revoked_kid?(kid)
      @revoked_kids.include?(kid.to_s)
    end

    def cutoff_for(foaf_id)
      @tokens_invalid_before[foaf_id.to_s]
    end

    def revoked_jti?(jti, now: Time.current)
      exp = @revoked_jtis[jti.to_s]
      exp.present? && exp > now
    end
  end
end
