require 'rails_helper'

# railsbackend is a thin proxy to auth.foaf.io for password reset. AuthFoafClient
# is stubbed (no real auth service in test); these assert the proxy forwards the
# right args and passes the (enumeration-safe) response through unchanged.
RSpec.describe 'V1 password reset proxy', type: :request do
  describe 'POST /v1/password_resets' do
    it 'forwards email + origin to auth and passes the response through' do
      expect(AuthFoafClient).to receive(:password_reset_request)
        .with(email: 'someone@example.test', origin: 'https://web.growoperative.app')
        .and_return([200, { 'status' => 'ok', 'message' => 'check your inbox' }])

      post '/v1/password_resets', params: { email: 'someone@example.test', origin: 'https://web.growoperative.app' }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('ok')
    end

    it 'passes an auth 4xx (e.g. bad origin) through unchanged' do
      allow(AuthFoafClient).to receive(:password_reset_request).and_return([422, { 'error' => 'Invalid origin' }])

      post '/v1/password_resets', params: { email: 'x@example.test', origin: 'https://evil.example.com' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('Invalid origin')
    end
  end

  describe 'POST /v1/password_resets/confirm' do
    it 'rejects a mismatched password before proxying' do
      expect(AuthFoafClient).not_to receive(:password_reset_confirm)

      post '/v1/password_resets/confirm', params: { token: 't', password: 'aaaaaaaa', password_confirmation: 'bbbbbbbb' }

      expect(response).to have_http_status(422)
    end

    it 'forwards token + password to auth and passes the response through' do
      expect(AuthFoafClient).to receive(:password_reset_confirm)
        .with(token: 'tok123', password: 'brand new pw')
        .and_return([200, { 'status' => 'ok' }])

      post '/v1/password_resets/confirm',
           params: { token: 'tok123', password: 'brand new pw', password_confirmation: 'brand new pw' }

      expect(response).to have_http_status(:ok)
    end
  end
end
