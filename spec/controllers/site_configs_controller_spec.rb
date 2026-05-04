require 'rails_helper'

RSpec.describe 'SiteConfigs API', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:user) { User.create!(user_name: 'sc_user', password: password) }
  let(:token) { "Bearer #{JwtGenerationService.new(user).token}" }
  let(:auth_headers) { { 'Authorization' => token } }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'GET /v1/site_config' do
    it 'requires authentication' do
      get '/v1/site_config'
      expect(response.status).to be_between(401, 403)
    end

    it 'returns defaults for a subnet with no config rows' do
      subnet = create(:subnet, seed_user: user)
      create(:subnet_membership, user: user, subnet: subnet, is_primary: true)

      get '/v1/site_config', headers: auth_headers
      expect(response).to have_http_status(200)

      body = JSON.parse(response.body)
      expect(body['subnet_id']).to eq(subnet.id)
      expect(body['config']['multi_role']).to eq(SiteConfig::DEFAULTS[:multi_role])
    end

    it 'returns the latest config version merged over defaults' do
      subnet = create(:subnet, seed_user: user)
      create(:subnet_membership, user: user, subnet: subnet, is_primary: true)
      create(:subnet_config, subnet: subnet, version: 1, config: { 'multi_role' => false, 'demo_mode' => true })

      get '/v1/site_config', headers: auth_headers
      expect(response).to have_http_status(200)

      body = JSON.parse(response.body)
      expect(body['config']['multi_role']).to eq(false)
      expect(body['config']['demo_mode']).to eq(true)
      expect(body['config']['chain_limit']).to eq(SiteConfig::DEFAULTS[:chain_limit])
    end

    it 'falls back to the user primary subnet when subnet_id is omitted' do
      primary = create(:subnet, name: 'Primary', seed_user: user)
      secondary = create(:subnet, name: 'Secondary', seed_user: user)
      create(:subnet_membership, user: user, subnet: primary, is_primary: true)
      create(:subnet_membership, user: user, subnet: secondary, is_primary: false)

      get '/v1/site_config', headers: auth_headers
      body = JSON.parse(response.body)
      expect(body['subnet_id']).to eq(primary.id)
      expect(body['subnet_name']).to eq('Primary')
    end

    it 'returns 403 when the user is not a member of the requested subnet' do
      other_user = User.create!(user_name: 'sc_other', password: password)
      foreign = create(:subnet, seed_user: other_user)

      get '/v1/site_config', params: { subnet_id: foreign.id }, headers: auth_headers
      expect(response).to have_http_status(403)
    end

    it 'returns 404 when the requested subnet does not exist' do
      get '/v1/site_config', params: { subnet_id: 999999 }, headers: auth_headers
      expect(response).to have_http_status(404)
    end
  end
end
