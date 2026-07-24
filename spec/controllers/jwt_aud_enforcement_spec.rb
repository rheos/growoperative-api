require 'rails_helper'

# Job 12 acceptance: master plan §12 (Audience Enforcement) +
# §JWT Contract → Bridge token contract.
#
# v1 tokens (sub = foaf_id string) MUST carry aud=growoperative or be
# rejected. Legacy HS256 tokens (sub absent or hash-shaped, no aud)
# are still accepted via the time-boxed bridge — these are app-store
# pre-Job-09 cookies that haven't rotated yet.
RSpec.describe 'JWT aud enforcement', type: :request do
  let!(:user) do
    User.create!(
      user_name: 'aud_user',
      email: 'aud_user@example.com',
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

  it 'accepts v1 tokens with aud=growoperative' do
    token = encode(
      sub: user.foaf_id,
      aud: 'growoperative',
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
    auth_get(token)
    expect(response).to have_http_status(:ok)
  end

  it 'rejects v1 tokens minted for a different app' do
    token = encode(
      sub: user.foaf_id,
      aud: 'orchardly',
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
    auth_get(token)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects v1 tokens with no aud claim at all' do
    # A v1 token (string sub) without aud is malformed under the new
    # contract — refuse rather than guess at the audience.
    token = encode(
      sub: user.foaf_id,
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
    auth_get(token)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'still accepts legacy HS256 tokens (nested-hash sub, no aud)' do
    # Pre-Job-09 cookies in the wild. Time-boxed bridge — Job 37 sunsets
    # this branch once the app-store min-supported-version flips.
    token = encode(
      sub: { user_id: { user_id: user.id } },
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
    auth_get(token)
    expect(response).to have_http_status(:ok)
  end

  it 'still accepts post-Job-09 legacy_uid-only tokens (no sub, no aud)' do
    token = encode(
      legacy_uid: user.id,
      jti: SecureRandom.uuid,
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i,
    )
    auth_get(token)
    expect(response).to have_http_status(:ok)
  end

  it 'configurable audience via FOAF_AUD env override' do
    # Lets orchardly-rails (or any future app) reuse the same lib with
    # a different configured audience without forking the verifier.
    decoded = JwtDecodingService.new(
      encode(
        sub: user.foaf_id,
        aud: 'orchardly',
        jti: SecureRandom.uuid,
        iat: Time.now.to_i,
        exp: 1.hour.from_now.to_i,
      ),
      audience: 'orchardly',
    ).decrypt!
    expect(decoded['aud']).to eq('orchardly')
    expect(decoded['sub']).to eq(user.foaf_id)
  end
end

# Master plan §Logging and Audit: every credential or bearer-token
# shape that could land in `params` or query strings must be redacted
# before logs leave the box. Pin the filter so future endpoints
# inheriting from ApiController can't quietly leak a new token shape.
RSpec.describe 'log filter coverage', type: :request do
  it 'redacts every credential / bearer / handle key in filter_parameters' do
    expected = %i[
      password
      current_password
      password_confirmation
      password_conformation
      user_name
      username
      email
      token
      jwt
      authorization
      authentication
      recovery_phrase
      seed_phrase
      invitation_code
      invited_code
      invite_code
    ]
    filters = Rails.application.config.filter_parameters
    expected.each do |key|
      matches = filters.any? do |filter|
        filter.to_s == key.to_s || (filter.respond_to?(:match?) && filter.match?(key.to_s))
      end
      expect(matches).to be(true), "filter_parameters missing #{key.inspect} - log shipping could leak it"
    end
  end
end
