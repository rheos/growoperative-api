require 'rails_helper'
require 'base64'

RSpec.describe 'auth.foaf.io round-trip contract', type: :request, skip_hooks: true do
  let(:audience) { 'growoperative' }
  let(:issuer) { 'auth.foaf.io' }
  let(:kid) { 'round-trip-kid' }
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:now) { Time.zone.parse('2026-07-24T00:00:00Z') }
  let(:password) { 'bobsentme!' }

  before do
    AuthJwksClient.reset!
    AuthRevocationSnapshot.reset!
    AuthJwksClient.http_get = ->(_url, _headers) { { keys: [jwk] }.to_json }
    AuthRevocationSnapshot.http_get = ->(_url, _headers) { snapshot_payload.to_json }
  end

  after do
    AuthJwksClient.reset!
    AuthRevocationSnapshot.reset!
  end

  def base64url_uint(integer)
    Base64.urlsafe_encode64(integer.to_s(2), padding: false)
  end

  def jwk
    {
      'kty' => 'RSA',
      'use' => 'sig',
      'alg' => 'RS256',
      'kid' => kid,
      'n' => base64url_uint(rsa.public_key.n),
      'e' => base64url_uint(rsa.public_key.e)
    }
  end

  def snapshot_payload(overrides = {})
    {
      generated_at: now.iso8601,
      audience: audience,
      revoked_jtis: [],
      tokens_invalid_before: {},
      revoked_kids: []
    }.merge(overrides)
  end

  def foaf_auth_token(user)
    claims = {
      iss: issuer,
      aud: audience,
      sub: user.foaf_id,
      iat: now.to_i,
      exp: (now + 1.year).to_i,
      jti: SecureRandom.uuid,
      user_name: user.user_name
    }
    claims[:email] = user.email if user.email.present?

    JWT.encode(claims, rsa, 'RS256', kid: kid)
  end

  def auth_headers(token)
    { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  it 'accepts a foaf-auth-issued RS256 bearer and refreshes through auth.foaf.io' do
    suffix = SecureRandom.hex(4)
    user = User.create!(
      user_name: "round_trip_#{suffix}",
      email: "round_trip_#{suffix}@example.test",
      password: password,
      password_confirmation: password
    )
    token = foaf_auth_token(user)

    expect(AuthFoafClient).to receive(:refresh_session).with(bearer: token).and_return([
      200,
      {
        'token' => 'fresh-rs256-token',
        'identity' => {
          'foaf_id' => user.foaf_id,
          'user_name' => user.user_name,
          'display_name' => user.display_name,
          'first_name' => user.first_name,
          'last_name' => user.last_name,
          'email' => user.email
        }
      }
    ])

    get '/v1/sessions', env: auth_headers(token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['token']).to eq('fresh-rs256-token')
    expect(body.dig('identity', 'foaf_id')).to eq(user.foaf_id)
    expect(body.dig('data', 'attributes', 'user_name')).to eq(user.user_name)
  end
end
