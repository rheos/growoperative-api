require 'rails_helper'

RSpec.describe 'Push Tokens API', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:user)  { User.create!(user_name: 'push_testuser', password: password) }
  let(:other) { User.create!(user_name: 'push_other', password: password) }
  let(:token) { "Bearer #{JwtGenerationService.new(user).token}" }
  let(:auth_headers) { { 'Authorization' => token } }

  let(:expo_token) { 'ExponentPushToken[aaaaaaaaaaaaaaaaaaaaaa]' }
  let(:device_id)  { 'device-abc' }

  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe 'POST /v1/push_tokens' do
    it 'creates a new row when none exists' do
      expect {
        post '/v1/push_tokens',
          params: { token: expo_token, device_id: device_id, platform: 'ios' },
          headers: auth_headers
      }.to change { user.push_tokens.count }.by(1)

      expect(response).to have_http_status(204)
      row = user.push_tokens.find_by(device_id: device_id)
      expect(row.token).to eq(expo_token)
      expect(row.platform).to eq('ios')
      expect(row.last_seen_at).to be_present
    end

    it 'updates token + last_seen_at when (user_id, device_id) already exists (rotation path)' do
      existing = user.push_tokens.create!(
        token: 'ExponentPushToken[oldoldoldoldoldoldold]',
        device_id: device_id,
        platform: 'ios',
        last_seen_at: 2.hours.ago
      )

      expect {
        post '/v1/push_tokens',
          params: { token: expo_token, device_id: device_id, platform: 'ios' },
          headers: auth_headers
      }.not_to change { user.push_tokens.count }

      expect(response).to have_http_status(204)
      existing.reload
      expect(existing.token).to eq(expo_token)
      expect(existing.last_seen_at).to be > 1.hour.ago
    end

    it 'transfers ownership when the token belongs to a different user' do
      stolen = other.push_tokens.create!(
        token: expo_token,
        device_id: 'other-device',
        platform: 'ios',
        last_seen_at: 1.day.ago
      )

      post '/v1/push_tokens',
        params: { token: expo_token, device_id: device_id, platform: 'ios' },
        headers: auth_headers

      expect(response).to have_http_status(204)
      stolen.reload
      expect(stolen.user_id).to eq(user.id)
      expect(stolen.device_id).to eq(device_id)
      # No duplicate row created — the existing token row was reassigned.
      expect(PushToken.where(token: expo_token).count).to eq(1)
      expect(other.push_tokens.count).to eq(0)
    end

    it 'returns 422 for an invalid platform instead of a 500' do
      expect {
        post '/v1/push_tokens',
          params: { token: expo_token, device_id: device_id, platform: 'web' },
          headers: auth_headers
      }.not_to change { PushToken.count }

      expect(response).to have_http_status(422)
      body = JSON.parse(response.body)
      expect(body['errors']).to be_present
    end

    it 'requires authentication' do
      post '/v1/push_tokens',
        params: { token: expo_token, device_id: device_id, platform: 'ios' }
      expect(response).to have_http_status(401)
    end
  end

  describe 'DELETE /v1/push_tokens' do
    it "deletes the current user's row(s) for the given device_id" do
      user.push_tokens.create!(token: expo_token, device_id: device_id, platform: 'ios')

      expect {
        delete '/v1/push_tokens', params: { device_id: device_id }, headers: auth_headers
      }.to change { user.push_tokens.count }.by(-1)

      expect(response).to have_http_status(204)
    end

    it 'does not delete rows belonging to other users' do
      others_row = other.push_tokens.create!(
        token: 'ExponentPushToken[bbbbbbbbbbbbbbbbbbbbbb]',
        device_id: device_id,
        platform: 'ios'
      )

      delete '/v1/push_tokens', params: { device_id: device_id }, headers: auth_headers

      expect(response).to have_http_status(204)
      expect(PushToken.exists?(others_row.id)).to eq(true)
    end

    it 'requires authentication' do
      delete '/v1/push_tokens', params: { device_id: device_id }
      expect(response).to have_http_status(401)
    end
  end
end
