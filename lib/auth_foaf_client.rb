require 'net/http'
require 'json'
require 'uri'

# Server-to-server client for the auth.foaf.io / dauth.foaf.io service.
# Job 42: railsbackend stops minting HS256 itself and instead asks
# auth.foaf.io to issue an RS256 token. The app keeps talking to
# railsbackend; only the token *origin* changes.
#
# Configured via:
#   FOAF_AUTH_BASE_URL          — https://auth.foaf.io / https://dauth.foaf.io
#   FOAF_AUTH_SERVICE_TOKEN     — bearer for /v1/internal/* endpoints
#   FOAF_AUD                    — audience to embed in tokens (default: growoperative)
#
# Read-only outside dev: do not call this for non-Growoperative audiences.
class AuthFoafClient
  class Error < StandardError
    attr_reader :status, :body
    def initialize(status:, body:)
      @status = status
      @body = body
      super("auth.foaf.io error #{status}: #{body.inspect}")
    end
  end

  DEFAULT_TIMEOUT = 10
  DEFAULT_AUDIENCE = 'growoperative'.freeze

  def self.login(user_name:, password:)
    new.post_json('/v1/sessions', {
      user_name: user_name,
      password: password,
      client_id: audience
    })
  end

  def self.refresh_session(bearer:)
    new.get_json('/v1/sessions', bearer: bearer)
  end

  def self.signup(user_name:, password:, email: nil, first_name: nil, last_name: nil, display_name: nil, recovery_phrase_acknowledged: false)
    body = {
      client_id: audience,
      user: {
        user_name: user_name,
        password: password,
        password_confirmation: password,
        email: email,
        first_name: first_name,
        last_name: last_name,
        display_name: display_name,
        recovery_phrase_acknowledged: recovery_phrase_acknowledged
      }.compact
    }
    new.post_json('/v1/signup', body)
  end

  def self.demo_token(foaf_id:, lifetime_seconds: nil)
    body = { foaf_id: foaf_id, audience: audience }
    body[:lifetime_seconds] = lifetime_seconds if lifetime_seconds
    new.post_json('/v1/internal/demo_tokens', body, service_token: true)
  end

  def self.change_password(current_password:, new_password:, bearer:)
    new.put_json('/v1/users/password', {
      current_password: current_password,
      password: new_password,
      password_confirmation: new_password
    }, bearer: bearer)
  end

  def self.audience
    ENV.fetch('FOAF_AUD', DEFAULT_AUDIENCE)
  end

  def self.base_url
    ENV.fetch('FOAF_AUTH_BASE_URL') { raise 'FOAF_AUTH_BASE_URL not configured' }
  end

  def self.service_token
    ENV.fetch('FOAF_AUTH_SERVICE_TOKEN') { raise 'FOAF_AUTH_SERVICE_TOKEN not configured' }
  end

  def post_json(path, body, service_token: false, bearer: nil)
    request_json(:post, path, body, service_token: service_token, bearer: bearer)
  end

  def put_json(path, body, service_token: false, bearer: nil)
    request_json(:put, path, body, service_token: service_token, bearer: bearer)
  end

  def get_json(path, bearer:)
    request_json(:get, path, nil, service_token: false, bearer: bearer)
  end

  private

  def request_json(method, path, body, service_token:, bearer:)
    uri = URI.join(self.class.base_url, path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = DEFAULT_TIMEOUT
    http.open_timeout = DEFAULT_TIMEOUT

    req_class =
      case method
      when :put then Net::HTTP::Put
      when :get then Net::HTTP::Get
      else Net::HTTP::Post
      end
    req = req_class.new(uri.request_uri)
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'
    if service_token
      req['Authorization'] = "Bearer #{self.class.service_token}"
    elsif bearer
      req['Authorization'] = "Bearer #{bearer}"
    end
    req.body = body.to_json if body

    res = http.request(req)
    parsed = res.body.present? ? safe_parse(res.body) : {}
    [Integer(res.code), parsed]
  end

  def safe_parse(body)
    JSON.parse(body)
  rescue JSON::ParserError
    { 'raw' => body }
  end
end
