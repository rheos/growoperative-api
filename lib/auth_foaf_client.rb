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

  def self.signup(user_name:, password:, email: nil, first_name: nil, last_name: nil, display_name: nil, recovery_phrase_acknowledged: false, invited_by_foaf_id: nil)
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
    # Optional minimum-viable contact-graph hint. When present, auth.foaf.io
    # creates a ContactEdge between the new identity and the inviter so the
    # FOAF contact graph reflects who-invited-whom even before Phase 6 wires
    # the full invitation primitive.
    body[:invited_by_foaf_id] = invited_by_foaf_id if invited_by_foaf_id
    new.post_json('/v1/signup', body)
  end

  def self.demo_token(foaf_id:, lifetime_seconds: nil)
    body = { foaf_id: foaf_id, audience: audience }
    body[:lifetime_seconds] = lifetime_seconds if lifetime_seconds
    new.post_json('/v1/internal/demo_tokens', body, service_token: true)
  end

  # Minimum-viable contact-graph hint. Records a connection between
  # two foaf_ids in auth.foaf.io's contact_edges. Used when an
  # existing user accepts an invitation that lives in railsbackend's
  # invitations table (Phase 6 unifies invitations into FOAF). Idempotent.
  def self.add_contact_edge(foaf_id_a:, foaf_id_b:)
    new.post_json('/v1/internal/contact_edges', {
      foaf_id_a: foaf_id_a,
      foaf_id_b: foaf_id_b
    }, service_token: true)
  end

  # Mint a pronounceable invite code via auth.foaf.io's invitation
  # primitive (Job 23, CVCV-CVCV like "mavo-leni"). Returns the code
  # plaintext exactly once — railsbackend stores the canonical form.
  # `target_app` is the app label (defaults to the audience).
  def self.create_invitation(inviter_foaf_id:, target_app: nil, expires_in_seconds: nil)
    body = {
      inviter_foaf_id: inviter_foaf_id,
      target_app: target_app || audience
    }
    body[:expires_in_seconds] = expires_in_seconds if expires_in_seconds
    new.post_json('/v1/internal/invitations', body, service_token: true)
  end

  # Mirror an avatar upload to auth.foaf.io. Bytes are base64'd into the
  # JSON body so we don't need multipart-post wrangling. The user's
  # bearer authorizes the call (auth.foaf.io issued it via railsbackend's
  # signup/login proxy). Response includes the canonical identity with
  # the new avatar_url.
  def self.upload_avatar(bytes:, content_type:, bearer:)
    require 'base64'
    new.put_json('/v1/users/avatar', {
      client_id: audience,
      data_base64: Base64.strict_encode64(bytes),
      content_type: content_type
    }, bearer: bearer)
  end

  def self.identity_by_handle(handle:)
    encoded = URI.encode_www_form_component(handle.to_s)
    new.get_public_json("/v1/users/by_handle/#{encoded}", base_url: public_base_url)
  end

  def self.change_password(current_password:, new_password:, bearer:)
    new.put_json('/v1/users/password', {
      client_id: audience,
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

  def self.public_base_url
    ENV.fetch('FOAF_AUTH_PUBLIC_BASE_URL', base_url)
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

  def get_public_json(path, base_url: nil)
    request_json(:get, path, nil, service_token: false, bearer: nil, base_url: base_url)
  end

  private

  def request_json(method, path, body, service_token:, bearer:, base_url: nil)
    uri = URI.join(base_url || self.class.base_url, path)
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
