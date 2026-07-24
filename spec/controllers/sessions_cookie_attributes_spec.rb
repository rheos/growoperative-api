require 'rails_helper'

# Job 38 sunset: platform cookie auth is retired. Login still returns a
# body token for current app web/native clients, but Rails must not mint a
# fresh auth cookie.
RSpec.describe 'Session cookie sunset', type: :request do
  let!(:user) do
    User.create!(
      user_name: 'csrf_user',
      email: 'csrf_user@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
  end

  describe 'POST /v1/sessions in non-development env' do
    it 'does not set a jwt cookie on successful login' do
      expect(Rails.env.development?).to be(false)

      post '/v1/sessions',
        params: { username: 'csrf_user', password: 'bobsentme!' },
        env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['token']).to be_present

      raw = response.headers['Set-Cookie']
      cookie_lines = raw.is_a?(Array) ? raw : raw.to_s.split("\n")
      jwt_cookie = cookie_lines.find { |h| h.start_with?('jwt=') && !h.match?(/expires=Thu, 01 Jan 1970/i) }
      expect(jwt_cookie).to be_nil, "jwt cookie should not be set. Raw Set-Cookie: #{raw.inspect}"
    end
  end

  describe 'DELETE /v1/sessions' do
    it 'blacklists the presented bearer token' do
      post '/v1/sessions',
        params: { username: 'csrf_user', password: 'bobsentme!' },
        env: { 'HTTPS' => 'on' }
      token = JSON.parse(response.body)['token']
      decoded = JWT.decode(token, ENV['SECRET_KEY_BASE'], true, { algorithm: 'HS256' }).first

      delete '/v1/sessions',
        env: { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
      expect(JwtBlacklist.exists?(jti: decoded['jti'])).to be(true)

      get '/v1/sessions',
        env: { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
