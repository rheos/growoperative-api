require 'rails_helper'

# Job 10 acceptance: v1 endpoint aliases + handle lookup adapter.
# Master plan refs: §Handle Lookup Contract, §10 Public Handle Lookup Fields.
RSpec.describe 'v1 user endpoints', type: :request do
  let(:password) { 'bobsentme!' }

  let!(:user) do
    User.create!(
      user_name: 'job10_user',
      email: 'job10_user@example.com',
      first_name: 'Job',
      last_name: 'Ten',
      display_name: 'JobTen',
      password: password,
      password_confirmation: password,
    )
  end

  def auth_headers
    token = JwtGenerationService.new(user).token
    { 'HTTP_AUTHORIZATION' => "Bearer #{token}", 'HTTPS' => 'on' }
  end

  def parsed
    JSON.parse(response.body)
  end

  describe 'GET /v1/users/profile' do
    it 'returns the v1 envelope with FoafIdentity for the current user' do
      get '/v1/users/profile', env: auth_headers
      expect(response).to have_http_status(:ok)
      expect(parsed['identity']['foaf_id']).to eq(user.foaf_id)
      expect(parsed['identity']['user_name']).to eq('job10_user')
    end

    it 'requires authentication' do
      get '/v1/users/profile', env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /v1/users/profile' do
    it 'updates first_name / last_name / display_name and returns the v1 envelope' do
      patch '/v1/users/profile',
        params: { user: { first_name: 'Updated', last_name: 'Name', display_name: 'Up' } },
        env: auth_headers
      expect(response).to have_http_status(:ok)
      expect(parsed['identity']['first_name']).to eq('Updated')
      expect(parsed['identity']['last_name']).to eq('Name')
      expect(parsed['identity']['display_name']).to eq('Up')
      user.reload
      expect(user.first_name).to eq('Updated')
    end

    it 'ignores fields outside the FoafIdentity allowlist (no role/admin escalation)' do
      patch '/v1/users/profile',
        params: { user: { display_name: 'Safe', invite_limit: 999_999, is_admin: true } },
        env: auth_headers
      expect(response).to have_http_status(:ok)
      user.reload
      # invite_limit is profile-shaped — must NOT be writable through the
      # v1 identity profile endpoint. (Admin route /v1/users/:id/set_invitation_limit
      # is the only legitimate path.)
      expect(user.invite_limit).not_to eq(999_999)
    end

    it 'accepts a flat body (no `user` wrapper)' do
      patch '/v1/users/profile',
        params: { display_name: 'Flat' },
        env: auth_headers
      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.display_name).to eq('Flat')
    end
  end

  describe 'PATCH /v1/users/password (alias)' do
    it 'proxies to auth.foaf.io and returns a refreshed token' do
      # Job 42: password change is owned by auth.foaf.io. railsbackend
      # forwards current_password + new password and surfaces the new
      # bearer; the local users.encrypted_password row is not touched
      # (and is irrelevant after Job 43's HS256 sunset).
      patch '/v1/users/password',
        params: { user: { current_password: password, password: 'newpw1234!', password_confirmation: 'newpw1234!' } },
        env: auth_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['token']).to be_a(String).and(be_present)
      expect(AuthFoafClient).to have_received(:change_password)
        .with(hash_including(current_password: password, new_password: 'newpw1234!'))
    end
  end

  describe 'GET /v1/users/by_handle/:handle' do
    it 'returns the four documented fields for a known handle' do
      get "/v1/users/by_handle/#{user.user_name}", env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)
      expect(parsed.keys).to contain_exactly('foaf_id', 'user_name', 'display_name', 'avatar_url')
      expect(parsed['foaf_id']).to eq(user.foaf_id)
    end

    it 'is case-insensitive on the handle (model normalizes lowercase)' do
      get "/v1/users/by_handle/JOB10_USER", env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)
      expect(parsed['user_name']).to eq('job10_user')
    end

    it 'returns 404 for an unknown handle (no email/role/subnet leak)' do
      get '/v1/users/by_handle/does_not_exist', env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:not_found)
      expect(parsed.keys).not_to include('email')
      expect(parsed.keys).not_to include('user_types')
      expect(parsed.keys).not_to include('subnet_memberships')
    end

    it 'does not require authentication' do
      get "/v1/users/by_handle/#{user.user_name}", env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /v1/users/handle_available' do
    it 'returns false for an active handle' do
      get '/v1/users/handle_available', params: { handle: 'job10_user' }, env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)
      expect(parsed).to eq('available' => false)
    end

    it 'returns true for a free handle that passes format' do
      get '/v1/users/handle_available', params: { handle: 'fresh_handle' }, env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)
      expect(parsed).to eq('available' => true)
    end

    it 'rejects too-short / structurally invalid handles with a structured reason' do
      # The model normalizes case on write, so uppercase is downcased
      # implicitly. Format check rejects length / leading-punctuation /
      # disallowed chars — symptoms a Phase-3 reserved-handle / cooldown
      # check would never need to see.
      get '/v1/users/handle_available', params: { handle: 'x' }, env: { 'HTTPS' => 'on' }
      expect(parsed).to eq('available' => false, 'reason' => 'invalid_format')

      get '/v1/users/handle_available', params: { handle: '_leading' }, env: { 'HTTPS' => 'on' }
      expect(parsed).to eq('available' => false, 'reason' => 'invalid_format')

      get '/v1/users/handle_available', params: { handle: 'has space' }, env: { 'HTTPS' => 'on' }
      expect(parsed).to eq('available' => false, 'reason' => 'invalid_format')
    end

    it 'is case-insensitive (lookup downcases input before format + active-identity check)' do
      get '/v1/users/handle_available', params: { handle: 'JOB10_USER' }, env: { 'HTTPS' => 'on' }
      expect(parsed['available']).to be(false)
    end

    it 'does not require authentication' do
      get '/v1/users/handle_available', params: { handle: 'whatever' }, env: { 'HTTPS' => 'on' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'rate limiting on handle endpoints' do
    around do |ex|
      original = Rails.cache
      # Memory store so increment is atomic in the test process.
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      ex.run
      Rails.cache = original
    end

    it 'returns 429 once HANDLE_LOOKUP_LIMIT is exceeded for a single IP' do
      limit = Api::V1::UsersController::HANDLE_LOOKUP_LIMIT
      (limit + 1).times do |i|
        get '/v1/users/handle_available', params: { handle: "probe_#{i}" }, env: { 'HTTPS' => 'on' }
      end
      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)).to eq('error' => 'rate_limited')
      expect(response.headers['Retry-After']).to be_present
    end
  end
end
