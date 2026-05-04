require 'rails_helper'

# Job 09 acceptance: api_controller#resolve_user_from_jwt is the bridge
# between v1 tokens (sub = foaf_id) and legacy HS256 tokens (sub =
# { user_id: { user_id: N } }, no legacy_uid). The rules below are
# transcribed from the master plan §JWT Contract → Bridge token contract;
# regressing them silently re-authenticates wrong users or breaks the
# bridge window before the app-store sunset.
RSpec.describe 'JWT bridge resolution', type: :request do
  let!(:user) do
    User.create!(
      user_name: 'bridge_user',
      email: 'bridge_user@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
  end

  let(:secret) { ENV['SECRET_KEY_BASE'] }

  def encode(claims)
    JWT.encode(claims, secret, 'HS256')
  end

  def auth_get(token)
    get '/v1/sessions',
      env: { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  describe 'v1 tokens (sub = foaf_id string)' do
    it 'authenticates when sub resolves to a user' do
      token = encode(
        sub: user.foaf_id,
        aud: 'growoperative',
        legacy_uid: user.id,
        iat: Time.now.to_i,
        exp: 1.hour.from_now.to_i,
        jti: SecureRandom.uuid,
      )
      auth_get(token)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig('identity', 'foaf_id')).to eq(user.foaf_id)
    end

    it 'rejects with 401 when sub is a UUID that does NOT resolve, even if legacy_uid would' do
      # The contract: a token whose `sub` is present but unresolvable must
      # be rejected. Falling through to `legacy_uid` here would silently
      # authenticate a different user (the app-store sunset risk we built
      # the bridge to avoid).
      token = encode(
        sub: SecureRandom.uuid, # not a foaf_id we know
        aud: 'growoperative',
        legacy_uid: user.id,
        iat: Time.now.to_i,
        exp: 1.hour.from_now.to_i,
        jti: SecureRandom.uuid,
      )
      auth_get(token)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'legacy HS256 tokens (sub absent or nested)' do
    it 'falls back to legacy_uid when sub is absent (post-09 bridge tokens for legacy paths)' do
      token = encode(
        legacy_uid: user.id,
        iat: Time.now.to_i,
        exp: 1.hour.from_now.to_i,
        jti: SecureRandom.uuid,
      )
      auth_get(token)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig('identity', 'foaf_id')).to eq(user.foaf_id)
    end

    it 'still resolves the historical double-nested sub shape' do
      # Tokens already in the wild (issued before job 09) carry
      # sub = { user_id: { user_id: N } } and have no legacy_uid.
      # These must keep working until the app-store sunset.
      token = encode(
        sub: { user_id: { user_id: user.id } },
        iat: Time.now.to_i,
        exp: 1.hour.from_now.to_i,
        jti: SecureRandom.uuid,
      )
      auth_get(token)
      expect(response).to have_http_status(:ok)
    end
  end
end
