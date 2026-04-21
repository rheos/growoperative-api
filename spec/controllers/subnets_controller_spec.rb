require 'rails_helper'

RSpec.describe 'Subnets admin API', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:superuser) do
    u = User.create!(user_name: 'sa_super', password: password)
    u.user_groups.create!(group_label: 'superuser')
    u
  end
  let(:regular) { User.create!(user_name: 'sa_reg', password: password) }
  let(:super_headers) { { 'Authorization' => "Bearer #{JwtGenerationService.new(user_id: superuser.id).token}" } }
  let(:reg_headers)   { { 'Authorization' => "Bearer #{JwtGenerationService.new(user_id: regular.id).token}" } }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'GET /v1/subnets' do
    it 'requires superuser' do
      get '/v1/subnets', headers: reg_headers
      expect(response).to have_http_status(403)
    end

    it 'lists every subnet with current config + member count' do
      seed = User.create!(user_name: 'sa_seed', password: password)
      subnet = create(:subnet, name: 'Test Net', seed_user: seed)
      create(:subnet_config, subnet: subnet, version: 1, config: { 'multi_role' => false })
      create(:subnet_membership, subnet: subnet)

      get '/v1/subnets', headers: super_headers
      expect(response).to have_http_status(200)

      body = JSON.parse(response.body)
      match = body['subnets'].find { |s| s['id'] == subnet.id }
      expect(match['name']).to eq('Test Net')
      expect(match['seed_user_name']).to eq('sa_seed')
      expect(match['member_count']).to eq(1)
      expect(match['config']['multi_role']).to eq(false)
      expect(match['version']).to eq(1)
    end
  end

  describe 'PATCH /v1/subnets/:id/config' do
    it 'requires superuser' do
      subnet = create(:subnet, seed_user: regular)
      patch "/v1/subnets/#{subnet.id}/config",
            params: { multi_role: false }.to_json,
            headers: reg_headers.merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(403)
    end

    it 'creates a new config version merging the updates over current' do
      subnet = create(:subnet, seed_user: superuser)
      create(:subnet_config, subnet: subnet, version: 1, config: { 'multi_role' => true, 'chain_limit' => 3 })

      patch "/v1/subnets/#{subnet.id}/config",
            params: { multi_role: false, visible_roles: ['broker'] }.to_json,
            headers: super_headers.merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(200)

      body = JSON.parse(response.body)
      expect(body['version']).to eq(2)
      expect(body['config']['multi_role']).to eq(false)
      expect(body['config']['visible_roles']).to eq(['broker'])
      expect(body['config']['chain_limit']).to eq(3) # preserved from prior version

      expect(subnet.subnet_configs.count).to eq(2)
      expect(subnet.subnet_configs.find_by(version: 2).changed_by_user_id).to eq(superuser.id)
    end

    it 'ignores unknown flags' do
      subnet = create(:subnet, seed_user: superuser)
      patch "/v1/subnets/#{subnet.id}/config",
            params: { multi_role: false, evil_key: 'mwahaha' }.to_json,
            headers: super_headers.merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(200)

      stored = subnet.reload.current_config.config
      expect(stored).not_to have_key('evil_key')
    end

    it 'rejects empty updates' do
      subnet = create(:subnet, seed_user: superuser)
      patch "/v1/subnets/#{subnet.id}/config",
            params: {}.to_json,
            headers: super_headers.merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(422)
    end
  end
end
