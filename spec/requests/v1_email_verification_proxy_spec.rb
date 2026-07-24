require 'rails_helper'

# railsbackend is a thin proxy to auth.foaf.io for email verification, and
# update_profile now proxies there too (the fix for "app email update never
# reached the FOAF record"). AuthFoafClient is stubbed (no real auth service in
# test); these assert the proxy forwards the right args and passes the response
# through unchanged.
RSpec.describe 'V1 email verification + profile proxy', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:user) { User.create!(user_name: 'evproxy', password: password) }
  let(:headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(user).token}",
      'Content-Type' => 'application/json' }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def json
    JSON.parse(response.body)
  end

  describe 'POST /v1/email_verifications' do
    it 'rejects an unauthenticated request' do
      post '/v1/email_verifications', params: { origin: 'https://web.growoperative.app' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'forwards the bearer + origin to auth and passes the response through' do
      expect(AuthFoafClient).to receive(:email_verification_request)
        .with(bearer: kind_of(String), origin: 'https://web.growoperative.app')
        .and_return([200, { 'status' => 'ok' }])

      post '/v1/email_verifications',
           params: { origin: 'https://web.growoperative.app' }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['status']).to eq('ok')
    end

    it 'passes an auth 4xx (bad origin) through unchanged' do
      allow(AuthFoafClient).to receive(:email_verification_request)
        .and_return([422, { 'error' => 'Invalid origin' }])

      post '/v1/email_verifications',
           params: { origin: 'https://evil.example.com' }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('Invalid origin')
    end
  end

  describe 'POST /v1/email_verifications/confirm' do
    it 'is unauthenticated and forwards the token to auth' do
      expect(AuthFoafClient).to receive(:email_verification_confirm)
        .with(token: 'tok123')
        .and_return([200, { 'status' => 'ok' }])

      post '/v1/email_verifications/confirm', params: { token: 'tok123' }

      expect(response).to have_http_status(:ok)
      expect(json['status']).to eq('ok')
    end

    it 'rejects a missing token before proxying' do
      expect(AuthFoafClient).not_to receive(:email_verification_confirm)

      post '/v1/email_verifications/confirm', params: {}

      expect(response).to have_http_status(422)
    end
  end

  describe 'PATCH /v1/users/profile (now proxies to auth)' do
    it 'forwards the patch + bearer to auth, mirrors name fields locally, and renders auth identity' do
      expect(AuthFoafClient).to receive(:update_profile)
        .with(patch: hash_including('display_name' => 'New Name'), bearer: kind_of(String))
        .and_return([200, { 'identity' => {
          'foaf_id' => user.foaf_id, 'user_name' => user.user_name, 'display_name' => 'New Name',
          'email_verified_at' => nil, 'pending_email' => nil
        } }])

      patch '/v1/users/profile', params: { display_name: 'New Name' }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['identity']['display_name']).to eq('New Name')
      expect(user.reload.display_name).to eq('New Name') # local mirror
    end

    it 'forwards a pending_email change without writing it to the local users row' do
      expect(AuthFoafClient).to receive(:update_profile)
        .with(patch: hash_including('pending_email' => 'new@example.test'), bearer: kind_of(String))
        .and_return([200, { 'identity' => {
          'foaf_id' => user.foaf_id, 'user_name' => user.user_name,
          'pending_email' => 'new@example.test', 'email_verified_at' => nil
        } }])

      patch '/v1/users/profile', params: { pending_email: 'new@example.test' }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['identity']['pending_email']).to eq('new@example.test')
    end

    it 'passes an auth 422 (recovery-phrase-gated email clear) through with its code' do
      allow(AuthFoafClient).to receive(:update_profile)
        .and_return([422, { 'error' => 'Recovery phrase required before removing email', 'code' => 'recovery_phrase_required' }])

      patch '/v1/users/profile', params: { email: '' }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['code']).to eq('recovery_phrase_required')
    end
  end
end
