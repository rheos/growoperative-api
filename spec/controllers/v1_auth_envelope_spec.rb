require 'rails_helper'

# Job 09 acceptance: login/signup/restore/demo all return the v1
# `{ token, identity }` envelope alongside app profile data in
# `data.attributes` while growoperative-rails still owns the local profile.
#
# The `identity` block is the FoafIdentity contract from the
# `foaf-auth/client` mapper; if a key is missing here the app's mapper
# either misses it or falls back to `legacy-jsonapi`. Both regress the
# Phase-2/3 cutover.
RSpec.describe 'v1 auth envelope', type: :request do
  let(:password) { 'bobsentme!' }

  let!(:user) do
    User.create!(
      user_name: 'envelope_user',
      email: 'envelope_user@example.com',
      first_name: 'Envelope',
      last_name: 'User',
      display_name: 'Env User',
      password: password,
      password_confirmation: password,
    )
  end

  def parsed
    JSON.parse(response.body)
  end

  shared_examples 'a v1 identity envelope' do
    it 'returns the FoafIdentity-shaped identity block' do
      identity = parsed['identity']
      expect(identity).to be_a(Hash)
      expect(identity['foaf_id']).to eq(user.foaf_id)
      expect(identity['user_name']).to eq(user.user_name)
      expect(identity['display_name']).to eq(user.display_name)
      expect(identity['first_name']).to eq(user.first_name)
      expect(identity['last_name']).to eq(user.last_name)
      expect(identity['email']).to eq(user.email)
      expect(identity).to have_key('avatar_url')
      expect(identity['created_at']).to be_a(String)
      expect(identity['updated_at']).to be_a(String)
    end

    it 'ships the app profile data.attributes block' do
      expect(parsed.dig('data', 'attributes', 'user_name')).to eq(user.user_name)
    end
  end

  shared_examples 'a v1 envelope response' do
    it 'returns top-level token + identity' do
      expect(parsed['token']).to be_a(String).and(be_present)
    end
    include_examples 'a v1 identity envelope'
  end

  describe 'POST /v1/sessions' do
    before do
      post '/v1/sessions',
        params: { username: user.user_name, password: password },
        env: { 'HTTPS' => 'on' }
    end

    it 'is 200 OK' do
      expect(response).to have_http_status(:ok)
    end

    include_examples 'a v1 envelope response'
  end

  describe 'GET /v1/sessions (restore)' do
    before do
      post '/v1/sessions',
        params: { username: user.user_name, password: password },
        env: { 'HTTPS' => 'on' }
      get '/v1/sessions',
        env: { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{JSON.parse(response.body)['token']}" }
    end

    it 'is 200 OK' do
      expect(response).to have_http_status(:ok)
    end

    # Token is only refreshed when the bearer is RS256 (Job 43 proxies
    # GET /v1/sessions to auth.foaf.io for v1 tokens; HS256 bridge
    # tokens get identity but not a refreshed token). In test env the
    # AuthFoafClient stub produces HS256 v1 tokens, so the proxy isn't
    # exercised here — identity envelope only.
    include_examples 'a v1 identity envelope'
  end

  describe 'POST /v1/demo/login' do
    before do
      user.user_groups.find_or_create_by!(group_label: 'demo')
      post '/v1/demo/login',
        params: { user_id: user.id },
        env: { 'HTTPS' => 'on' }
    end

    it 'is 200 OK' do
      expect(response).to have_http_status(:ok)
    end

    include_examples 'a v1 envelope response'
  end
end
