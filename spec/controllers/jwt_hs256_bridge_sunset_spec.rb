require 'rails_helper'

# Job 37 acceptance: HS256 bridge sunset.
#
# When FOAF_AUTH_HS256_BRIDGE_ENABLED is "false", the Rails JWT verifier
# rejects every HS256 token regardless of shape. The 401 response carries
# `code: client_too_old_auth_bridge_expired` so the app can clear local
# auth state and route the user back through login. The flag is env-only
# so we can flip the cutover without a code deploy and roll it back the
# same way.
RSpec.describe 'JWT HS256 bridge sunset (Job 37)', type: :request do
  let!(:user) do
    User.create!(
      user_name: 'bridge_user',
      email: 'bridge_user@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
  end

  let(:secret) { ENV['SECRET_KEY_BASE'] }

  def encode_hs256(claims)
    JWT.encode(claims, secret, 'HS256')
  end

  def auth_get(token)
    get '/v1/sessions',
      env: { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  let(:legacy_hash_sub_token) do
    encode_hs256(
      sub: { user_id: { user_id: user.id } },
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
  end

  let(:legacy_uid_only_token) do
    encode_hs256(
      legacy_uid: user.id,
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
  end

  let(:v1_hs256_token) do
    encode_hs256(
      sub: user.foaf_id,
      aud: 'growoperative',
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
  end

  context 'with the bridge enabled (default behavior)' do
    around do |example|
      previous = ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED']
      ENV.delete('FOAF_AUTH_HS256_BRIDGE_ENABLED')
      example.run
    ensure
      ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED'] = previous
    end

    it 'still accepts legacy hash-shaped sub tokens' do
      auth_get(legacy_hash_sub_token)
      expect(response).to have_http_status(:ok)
    end

    it 'still accepts legacy_uid-only tokens' do
      auth_get(legacy_uid_only_token)
      expect(response).to have_http_status(:ok)
    end

    it 'still accepts v1-shaped HS256 tokens' do
      auth_get(v1_hs256_token)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with the bridge disabled' do
    around do |example|
      previous = ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED']
      ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED'] = 'false'
      example.run
    ensure
      ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED'] = previous
    end

    it 'rejects legacy hash-shaped sub tokens with the bridge-expired code' do
      auth_get(legacy_hash_sub_token)
      expect(response).to have_http_status(:unauthorized)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('client_too_old_auth_bridge_expired')
    end

    it 'rejects legacy_uid-only tokens with the bridge-expired code' do
      auth_get(legacy_uid_only_token)
      expect(response).to have_http_status(:unauthorized)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('client_too_old_auth_bridge_expired')
    end

    it 'rejects v1-shaped HS256 tokens with the bridge-expired code' do
      auth_get(v1_hs256_token)
      expect(response).to have_http_status(:unauthorized)
      body = JSON.parse(response.body)
      expect(body['code']).to eq('client_too_old_auth_bridge_expired')
    end

    it 'still accepts RS256 auth.foaf.io tokens (flag does not affect RS256 path)' do
      # We don't issue a real RS256 token here — that path is exercised in
      # auth_jwks_verifier_spec / Job 16/17 specs. We just assert the flag
      # only short-circuits the HS256 branch.
      service = JwtDecodingService.new('not.a.real.token')
      header = { 'alg' => 'RS256', 'kid' => 'test' }
      allow(JWT).to receive(:decode).with('not.a.real.token', nil, false).and_return([{}, header])
      expect(service).to receive(:decrypt_auth_token!).with(header).and_return({ 'sub' => 'foaf-id' })
      expect(service.decrypt!).to eq({ 'sub' => 'foaf-id' })
    end
  end

  describe '.hs256_bridge_enabled?' do
    around do |example|
      previous = ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED']
      example.run
    ensure
      ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED'] = previous
    end

    it 'defaults to enabled when unset' do
      ENV.delete('FOAF_AUTH_HS256_BRIDGE_ENABLED')
      expect(JwtDecodingService.hs256_bridge_enabled?).to be(true)
    end

    it 'defaults to enabled when blank' do
      ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED'] = ''
      expect(JwtDecodingService.hs256_bridge_enabled?).to be(true)
    end

    it 'is enabled when set to "true"' do
      ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED'] = 'true'
      expect(JwtDecodingService.hs256_bridge_enabled?).to be(true)
    end

    %w[false 0 no off FALSE].each do |val|
      it "is disabled when set to #{val.inspect}" do
        ENV['FOAF_AUTH_HS256_BRIDGE_ENABLED'] = val
        expect(JwtDecodingService.hs256_bridge_enabled?).to be(false)
      end
    end
  end
end
