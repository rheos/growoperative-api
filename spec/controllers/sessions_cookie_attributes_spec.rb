require 'rails_helper'

# CSRF defense lives at the cookie's SameSite attribute (audit at
# foaf-auth/docs/audits/csrf-coverage-audit.md). These specs lock that
# attribute so a future change to api_controller.rb cannot silently
# regress the production cookie back to SameSite=None.
RSpec.describe 'Session cookie attributes', type: :request do
  let!(:user) do
    User.create!(
      user_name: 'csrf_user',
      email: 'csrf_user@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
  end

  describe 'POST /v1/sessions in non-development env' do
    it 'sets the jwt cookie with SameSite=Lax, HttpOnly, Secure' do
      # Test env hits the non-development branch in api_controller#assign_jwt_cookies
      expect(Rails.env.development?).to be(false)

      # Secure cookies require HTTPS; without this header the cookie is dropped.
      post '/v1/sessions',
        params: { username: 'csrf_user', password: 'bobsentme!' },
        env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)

      # Set-Cookie may be a single string with newline separators or an Array.
      raw = response.headers['Set-Cookie']
      cookie_lines = raw.is_a?(Array) ? raw : raw.to_s.split("\n")
      set_cookie_header = cookie_lines.find { |h| h.start_with?('jwt=') }
      expect(set_cookie_header).to be_present,
        "jwt cookie not set on successful login. Raw Set-Cookie: #{raw.inspect}"

      expect(set_cookie_header).to match(/;\s*SameSite=Lax/i),
        "expected SameSite=Lax in production cookie; got: #{set_cookie_header}"
      expect(set_cookie_header).to match(/;\s*HttpOnly/i),
        "expected HttpOnly in production cookie; got: #{set_cookie_header}"
      expect(set_cookie_header).to match(/;\s*secure/i),
        "expected Secure in production cookie; got: #{set_cookie_header}"
      expect(set_cookie_header).not_to match(/SameSite=None/i),
        "production cookie regressed to SameSite=None; CSRF surface reopened"
    end
  end
end
