require 'rails_helper'
require 'base64'

RSpec.describe 'auth.foaf.io JWKS verifier', skip_hooks: true do
  let(:audience) { 'growoperative' }
  let(:kid) { 'prod-test-kid' }
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:user) do
    User.create!(
      user_name: 'rs256user',
      email: 'rs256user@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!'
    )
  end
  let(:now) { Time.zone.parse('2026-05-05T17:00:00Z') }

  before do
    User.delete_all
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

  def token(overrides = {}, signing_key: rsa)
    claims = {
      iss: 'auth.foaf.io',
      aud: audience,
      sub: user.foaf_id,
      iat: now.to_i,
      exp: 1.hour.from_now.to_i,
      jti: 'jti-valid'
    }.merge(overrides)
    JWT.encode(claims, signing_key, 'RS256', kid: kid)
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

  it 'verifies a valid auth.foaf.io RS256 token through JWKS' do
    decoded = JwtDecodingService.new(token).decrypt!

    expect(decoded['iss']).to eq('auth.foaf.io')
    expect(decoded['aud']).to eq(audience)
    expect(decoded['sub']).to eq(user.foaf_id)
  end

  it 'rejects a revoked jti from the revocation snapshot' do
    AuthRevocationSnapshot.http_get = ->(_url, _headers) do
      snapshot_payload(revoked_jtis: [{ jti: 'jti-valid', exp: 1.hour.from_now.iso8601 }]).to_json
    end

    expect { JwtDecodingService.new(token).decrypt! }
      .to raise_error(JwtDecodingService::JWTDecodingError, /revoked/)
  end

  it 'rejects a token issued before tokens_invalid_before' do
    AuthRevocationSnapshot.http_get = ->(_url, _headers) do
      snapshot_payload(tokens_invalid_before: { user.foaf_id => (now + 10.seconds).iso8601 }).to_json
    end

    expect { JwtDecodingService.new(token).decrypt! }
      .to raise_error(JwtDecodingService::JWTDecodingError, /cutoff/)
  end

  it 'rejects a revoked kid even when JWKS still publishes the key' do
    AuthRevocationSnapshot.http_get = ->(_url, _headers) do
      snapshot_payload(revoked_kids: [{ kid: kid, retired_at: now.iso8601 }]).to_json
    end

    expect { JwtDecodingService.new(token).decrypt! }
      .to raise_error(JwtDecodingService::JWTDecodingError, /signing key/)
  end

  it 'fails closed for an unknown kid after a refresh' do
    AuthJwksClient.http_get = ->(_url, _headers) { { keys: [] }.to_json }

    expect { JwtDecodingService.new(token).decrypt! }
      .to raise_error(JwtDecodingService::JWTDecodingError, /unknown/)
  end

  it 'serves a known kid from last-good JWKS during an outage' do
    AuthJwksClient.public_key_for(kid, now: now)
    AuthJwksClient.http_get = ->(_url, _headers) { raise AuthJwksClient::FetchError, 'auth outage' }

    key = AuthJwksClient.public_key_for(kid, now: now + 2.hours)

    expect(key.to_pem).to eq(rsa.public_key.to_pem)
  end

  it 'keeps the existing HS256 bridge token path working' do
    legacy_token = JWT.encode(
      {
        sub: { user_id: { user_id: user.id } },
        iat: now.to_i,
        exp: 1.hour.from_now.to_i,
        jti: SecureRandom.uuid
      },
      ENV['SECRET_KEY_BASE'],
      'HS256'
    )

    decoded = JwtDecodingService.new(legacy_token).decrypt!

    expect(decoded.dig('sub', 'user_id', 'user_id')).to eq(user.id)
  end
end
