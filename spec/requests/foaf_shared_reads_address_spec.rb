require 'rails_helper'
require 'base64'

# Prompt 7 (Phase 5, one-address-per-identity) — reads-first / shadow-only.
#
# Pins the address-read/display seam: with FOAF_SHARED_READS on, the current
# user's own foaf_address is resolved from the verified JWT claim and
# shadow-diffed against users.foaf_address (mismatch is logged, never fatal).
# With the flag off, behavior is unchanged (DB value, no claim read).
#
# The seam is driven end-to-end through the real auth.foaf.io RS256 verifier
# and surfaced via GET /v1/sessions' identity payload. The refresh_session
# proxy is stubbed to return no `identity` so the locally-built identity
# payload (which carries the resolver output) is what the client sees.
RSpec.describe 'FOAF_SHARED_READS address read', type: :request, skip_hooks: true do
  let(:audience) { 'growoperative' }
  let(:issuer) { 'auth.foaf.io' }
  let(:kid) { 'shared-reads-kid' }
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:now) { Time.zone.parse('2026-08-15T00:00:00Z') }
  let(:password) { 'bobsentme!' }
  # skip_hooks keeps DatabaseCleaner off, so rows persist across examples and the
  # unique foaf_address index would collide. Give each example its own pair.
  let(:db_address) { "0xdb#{SecureRandom.hex(19)}" }
  let(:claim_address) { "0xc1#{SecureRandom.hex(19)}" }

  before do
    AuthJwksClient.reset!
    AuthRevocationSnapshot.reset!
    AuthJwksClient.http_get = ->(_url, _headers) { { keys: [jwk] }.to_json }
    AuthRevocationSnapshot.http_get = ->(_url, _headers) { snapshot_payload.to_json }
    # Keep the local identity payload intact: no `identity` in the refresh body
    # means sessions#show returns the resolver-built identity, not a proxy copy.
    allow(AuthFoafClient).to receive(:refresh_session).and_return([200, { 'token' => 'fresh-token' }])
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
      'kty' => 'RSA', 'use' => 'sig', 'alg' => 'RS256', 'kid' => kid,
      'n' => base64url_uint(rsa.public_key.n),
      'e' => base64url_uint(rsa.public_key.e)
    }
  end

  def snapshot_payload(overrides = {})
    {
      generated_at: now.iso8601, audience: audience,
      revoked_jtis: [], tokens_invalid_before: {}, revoked_kids: []
    }.merge(overrides)
  end

  def rs256_token(user, overrides: {})
    claims = {
      iss: issuer, aud: audience, sub: user.foaf_id,
      iat: now.to_i, exp: (now + 1.year).to_i,
      jti: SecureRandom.uuid, user_name: user.user_name
    }.merge(overrides)
    JWT.encode(claims, rsa, 'RS256', kid: kid)
  end

  def auth_headers(token)
    { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  def make_user(suffix, foaf_address:)
    User.create!(
      user_name: "shared_reads_#{suffix}_#{SecureRandom.hex(4)}",
      password: password, password_confirmation: password,
      foaf_address: foaf_address
    )
  end

  def identity_foaf_address_from(response)
    JSON.parse(response.body).dig('identity', 'foaf_address')
  end

  context 'when FOAF_SHARED_READS is on' do
    before { allow(Foaf::Config).to receive(:shared_reads?).and_return(true) }

    it 'returns the claim address (not the DB address) for the display path' do
      user = make_user('claim_wins', foaf_address: db_address)
      token = rs256_token(user, overrides: { foaf_address: claim_address })

      get '/v1/sessions', env: auth_headers(token)

      expect(response).to have_http_status(:ok)
      expect(identity_foaf_address_from(response)).to eq(claim_address)
    end

    it 'logs a warning (and does not crash) when the claim address differs from the DB address' do
      user = make_user('mismatch', foaf_address: db_address)
      token = rs256_token(user, overrides: { foaf_address: claim_address })

      expect(Rails.logger).to receive(:warn).with(/\[FOAF_SHARED_READS\] address mismatch for foaf_id=#{user.foaf_id}/).at_least(:once)

      get '/v1/sessions', env: auth_headers(token)

      expect(response).to have_http_status(:ok)
    end

    it 'logs a stale-token warning when the token carries no address but the user has one (Task B)' do
      user = make_user('stale', foaf_address: db_address)
      token = rs256_token(user) # no foaf_address claim

      expect(Rails.logger).to receive(:warn).with(/\[FOAF_SHARED_READS\] stale token for foaf_id=#{user.foaf_id}/).at_least(:once)

      get '/v1/sessions', env: auth_headers(token)

      expect(response).to have_http_status(:ok)
      # Reads are not blocked; the DB address is still displayed.
      expect(identity_foaf_address_from(response)).to eq(db_address)
    end
  end

  context 'when FOAF_SHARED_READS is off' do
    before { allow(Foaf::Config).to receive(:shared_reads?).and_return(false) }

    it 'returns the DB address and never reads the claim (additive/guarded)' do
      user = make_user('flag_off', foaf_address: db_address)
      token = rs256_token(user, overrides: { foaf_address: claim_address })

      expect(Rails.logger).not_to receive(:warn).with(/\[FOAF_SHARED_READS\]/)

      get '/v1/sessions', env: auth_headers(token)

      expect(response).to have_http_status(:ok)
      expect(identity_foaf_address_from(response)).to eq(db_address)
    end
  end
end
