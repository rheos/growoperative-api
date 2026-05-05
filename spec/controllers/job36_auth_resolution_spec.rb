require 'rails_helper'
require 'base64'

RSpec.describe 'Job 36 auth.foaf.io token resolution', type: :request do
  let(:audience) { 'growoperative' }
  let(:kid) { 'job36-kid' }
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:now) { Time.zone.parse('2026-05-05T19:30:00Z') }
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

  def rs256_token(sub:, aud: audience, overrides: {})
    claims = {
      iss: 'auth.foaf.io',
      aud: aud,
      sub: sub,
      iat: now.to_i,
      exp: 1.hour.from_now.to_i,
      jti: SecureRandom.uuid,
      user_name: "user_#{sub.delete('-')[0, 8]}",
      email: "user_#{sub.delete('-')[0, 8]}@example.com"
    }.merge(overrides)
    JWT.encode(claims, rsa, 'RS256', kid: kid)
  end

  def auth_headers(token)
    { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  it 'resolves a valid RS256 sub to the local users.foaf_id and returns app profile fields' do
    user = User.create!(user_name: 'job36_valid', password: password, password_confirmation: password)
    user.user_groups.create!(group_label: 'producer')

    get '/v1/profile', env: auth_headers(rs256_token(sub: user.foaf_id))

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['id']).to eq(user.id)
    expect(body['foaf_id']).to eq(user.foaf_id)
    expect(body['role']).to eq('producer')
    expect(body['user_types'].map { |row| row['group_label'] }).to include('producer')
    expect(body).not_to have_key('email')
    expect(body).not_to have_key('user_name')
  end

  it 'rejects an auth.foaf.io token minted for another audience' do
    user = User.create!(user_name: 'job36_wrong_aud', password: password, password_confirmation: password)

    get '/v1/profile', env: auth_headers(rs256_token(sub: user.foaf_id, aud: 'orchardly'))

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a valid token whose foaf_id has no local Growoperative profile outside onboarding' do
    get '/v1/profile', env: auth_headers(rs256_token(sub: SecureRandom.uuid))

    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows a no-local-profile token to read onboarding status' do
    get '/v1/onboarding/status',
      params: { invitation_code: 'missing' },
      env: auth_headers(rs256_token(sub: SecureRandom.uuid))

    expect(response).to have_http_status(:not_found)
  end

  it 'creates the local profile when a valid no-local-profile identity onboards' do
    inviter = User.create!(user_name: 'job36_inviter', password: password, password_confirmation: password)
    inviter.user_groups.create!(group_label: 'producer')
    invitation = Invitation.create!(user: inviter, user_type: 'consumer', status: 'pending')
    foaf_id = SecureRandom.uuid

    post '/v1/onboarding',
      params: { invitation_code: invitation.invitation_code },
      env: auth_headers(rs256_token(sub: foaf_id, overrides: { user_name: 'job36_newbie' }))

    expect(response).to have_http_status(:ok)
    user = User.find_by!(foaf_id: foaf_id)
    expect(user.user_name).to eq('job36_newbie')
    expect(user.user_groups.pluck(:group_label)).to include('consumer')
  end

  it 'rejects a token whose local profile is deleted' do
    user = User.create!(user_name: 'job36_deleted', password: password, password_confirmation: password)
    user.update!(deleted_at: Time.current)

    get '/v1/profile', env: auth_headers(rs256_token(sub: user.foaf_id))

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a token whose local profile is disabled' do
    user = User.create!(user_name: 'job36_disabled', password: password, password_confirmation: password)
    user.update!(disabled_at: Time.current)

    get '/v1/profile', env: auth_headers(rs256_token(sub: user.foaf_id))

    expect(response).to have_http_status(:unauthorized)
  end
end
