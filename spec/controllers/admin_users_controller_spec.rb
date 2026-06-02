require 'rails_helper'

RSpec.describe 'Admin users API', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:superuser) do
    u = User.create!(user_name: 'au_super', password: password)
    u.user_groups.create!(group_label: 'superuser')
    u
  end
  let(:demo_superuser) do
    u = User.create!(user_name: 'au_demo_super', password: password)
    u.user_groups.create!(group_label: 'superuser')
    u.user_groups.create!(group_label: 'demo')
    u
  end
  let(:regular) { User.create!(user_name: 'au_regular', password: password) }
  let(:super_headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(superuser).token}",
      'Content-Type' => 'application/json' }
  end
  let(:demo_headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(demo_superuser).token}",
      'Content-Type' => 'application/json' }
  end
  let(:regular_headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(regular).token}",
      'Content-Type' => 'application/json' }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def json
    JSON.parse(response.body)
  end

  describe 'authorization' do
    it 'requires a non-demo superuser' do
      get '/v1/admin/users', params: { q: 'alice' }
      expect(response).to have_http_status(:unauthorized)

      get '/v1/admin/users', params: { q: 'alice' }, headers: regular_headers
      expect(response).to have_http_status(:forbidden)

      get '/v1/admin/users', params: { q: 'alice' }, headers: demo_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /v1/admin/users' do
    it 'proxies identity search and writes an audit row' do
      allow(AuthFoafClient).to receive(:search_users)
        .with(query: 'ali', limit: 20, include_deleted: false)
        .and_return([200, {
          'matches' => [
            { 'foaf_id' => 'foaf-1', 'user_name' => 'alice', 'email' => 'alice@example.test' }
          ]
        }])

      get '/v1/admin/users', params: { q: 'ali' }, headers: super_headers

      expect(response).to have_http_status(:ok)
      expect(json['matches'].first['user_name']).to eq('alice')
      audit = AuditLog.last
      expect(audit.action).to eq('admin.users.search')
      expect(audit.actor_user_id).to eq(superuser.id)
      expect(audit.metadata).to include('query' => 'ali', 'result_count' => 1)
    end

    it 'passes include_deleted and clamps high limits before proxying' do
      allow(AuthFoafClient).to receive(:search_users)
        .with(query: 'deleted', limit: 50, include_deleted: true)
        .and_return([200, { 'matches' => [] }])

      get '/v1/admin/users',
          params: { q: 'deleted', limit: 500, include_deleted: '1' },
          headers: super_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /v1/admin/users/:foaf_id' do
    it 'composes auth identity with local Growoperative profile' do
      target = User.create!(user_name: 'au_target', password: password, foaf_id: SecureRandom.uuid)
      target.user_groups.create!(group_label: 'producer')
      subnet = create(:subnet, name: 'Admin Net', seed_user: superuser)
      target.subnet_memberships.create!(subnet: subnet, is_primary: true)

      allow(AuthFoafClient).to receive(:get_user)
        .with(foaf_id: target.foaf_id)
        .and_return([200, {
          'identity' => {
            'foaf_id' => target.foaf_id,
            'user_name' => 'au_target',
            'display_name' => 'Target User',
            'email' => 'target@example.test'
          }
        }])

      get "/v1/admin/users/#{target.foaf_id}", headers: super_headers

      expect(response).to have_http_status(:ok)
      body = json
      expect(body['identity']).to include('foaf_id' => target.foaf_id)
      expect(body['profile']).to include(
        'growoperative_user_id' => target.id,
        'roles' => ['producer'],
        'is_demo' => false,
        'item_count' => 0
      )
      expect(body['profile']['invite_limit']).to include('remaining' => 3, 'total' => 3)
      expect(body['profile']['subnet_memberships'].first).to include('subnet_name' => 'Admin Net')
      expect(AuditLog.last.action).to eq('admin.users.view')
    end

    it 'returns profile nil when the identity has no local user row' do
      allow(AuthFoafClient).to receive(:get_user)
        .with(foaf_id: 'identity-only')
        .and_return([200, { 'identity' => { 'foaf_id' => 'identity-only', 'user_name' => 'elsewhere' } }])

      get '/v1/admin/users/identity-only', headers: super_headers

      expect(response).to have_http_status(:ok)
      expect(json['profile']).to be_nil
    end

    it 'passes through auth-service misses' do
      allow(AuthFoafClient).to receive(:get_user)
        .with(foaf_id: 'missing')
        .and_return([404, { 'error' => 'identity_not_found' }])

      get '/v1/admin/users/missing', headers: super_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to include('error' => 'identity_not_found')
      expect(AuditLog.last.status).to eq('failed')
    end
  end

  describe 'POST /v1/admin/users/:foaf_id/reset_password' do
    it 'resets through auth.foaf.io and audits without logging the password' do
      foaf_id = SecureRandom.uuid
      allow(AuthFoafClient).to receive(:get_user)
        .with(foaf_id: foaf_id)
        .and_return([200, { 'identity' => { 'foaf_id' => foaf_id, 'user_name' => 'reset_target' } }])
      allow(AuthFoafClient).to receive(:admin_reset_password)
        .with(foaf_id: foaf_id, new_password: 'new password 123')
        .and_return([200, {
          'foaf_id' => foaf_id,
          'tokens_invalid_before' => '2026-06-01T12:00:00Z',
          'sessions_invalidated' => true
        }])

      post "/v1/admin/users/#{foaf_id}/reset_password",
           params: { new_password: 'new password 123' }.to_json,
           headers: super_headers

      expect(response).to have_http_status(:ok)
      expect(json).to include('sessions_invalidated' => true)

      audit = AuditLog.last
      expect(audit.action).to eq('admin.users.reset_password')
      expect(audit.metadata).to include(
        'target_foaf_id' => foaf_id,
        'target_user_name' => 'reset_target',
        'tokens_invalid_before' => '2026-06-01T12:00:00Z'
      )
      expect(audit.metadata.to_json).not_to include('new password 123')
    end

    it 'rejects too-short passwords before calling auth.foaf.io' do
      expect(AuthFoafClient).not_to receive(:admin_reset_password)

      post '/v1/admin/users/someone/reset_password',
           params: { new_password: 'short' }.to_json,
           headers: super_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'allows a superuser to reset their own password through this path' do
      allow(AuthFoafClient).to receive(:get_user)
        .with(foaf_id: superuser.foaf_id)
        .and_return([200, { 'identity' => { 'foaf_id' => superuser.foaf_id, 'user_name' => superuser.user_name } }])
      allow(AuthFoafClient).to receive(:admin_reset_password)
        .with(foaf_id: superuser.foaf_id, new_password: 'new password 123')
        .and_return([200, {
          'foaf_id' => superuser.foaf_id,
          'tokens_invalid_before' => '2026-06-01T12:00:00Z',
          'sessions_invalidated' => true
        }])

      post "/v1/admin/users/#{superuser.foaf_id}/reset_password",
           params: { new_password: 'new password 123' }.to_json,
           headers: super_headers

      expect(response).to have_http_status(:ok)
    end
  end
end
