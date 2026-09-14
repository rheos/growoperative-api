require 'rails_helper'

RSpec.describe 'Admin currencies API', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:superuser) do
    u = User.create!(user_name: 'cur_super', password: password)
    u.user_groups.create!(group_label: 'superuser')
    u
  end
  let(:regular) { User.create!(user_name: 'cur_reg', password: password) }
  let(:super_headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(superuser).token}",
      'Content-Type' => 'application/json' }
  end
  let(:reg_headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(regular).token}",
      'Content-Type' => 'application/json' }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'GET /v1/admin/currencies' do
    it 'requires superuser' do
      get '/v1/admin/currencies', headers: reg_headers
      expect(response).to have_http_status(403)
    end

    it 'lists the builtin catalog' do
      get '/v1/admin/currencies', headers: super_headers
      expect(response).to have_http_status(200)

      body = JSON.parse(response.body)
      codes = body['currencies'].map { |c| c['code'] }
      expect(codes).to include('CAD', 'USD', 'EUR', 'MXN', 'CRC', 'THB')
      cad = body['currencies'].find { |c| c['code'] == 'CAD' }
      expect(cad['name']).to eq('Canadian dollar')
      expect(cad['locale']).to eq('en-CA')
      expect(cad['active']).to eq(true)
    end
  end

  describe 'POST /v1/admin/currencies' do
    it 'requires superuser' do
      post '/v1/admin/currencies',
           params: { code: 'THB' }.to_json,
           headers: reg_headers
      expect(response).to have_http_status(403)
    end

    it 'registers a new ISO code' do
      post '/v1/admin/currencies',
           params: { code: 'php', name: 'Philippine peso', locale: 'en-PH' }.to_json,
           headers: super_headers
      expect(response).to have_http_status(201)

      body = JSON.parse(response.body)
      expect(body['code']).to eq('PHP')
      expect(body['name']).to eq('Philippine peso')
      expect(body['locale']).to eq('en-PH')
      expect(body['active']).to eq(true)
      expect(SiteConfig.normalize_currency('PHP')).to eq('PHP')
    end

    it 'defaults name to the code and locale to en' do
      post '/v1/admin/currencies',
           params: { code: 'ARS' }.to_json,
           headers: super_headers
      expect(response).to have_http_status(201)

      body = JSON.parse(response.body)
      expect(body['code']).to eq('ARS')
      expect(body['name']).to eq('ARS')
      expect(body['locale']).to eq('en')
    end

    it 'rejects a code that is already in the catalog' do
      post '/v1/admin/currencies',
           params: { code: 'EUR' }.to_json,
           headers: super_headers
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to eq('Currency already registered')
    end

    it 'rejects a non-ISO code' do
      post '/v1/admin/currencies',
           params: { code: 'XXXX' }.to_json,
           headers: super_headers
      expect(response).to have_http_status(422)
    end

    it 'lets a subnet pick Thai baht from the starter list' do
      subnet = create(:subnet, seed_user: superuser)
      create(:subnet_membership, user: superuser, subnet: subnet, is_primary: true)

      patch "/v1/subnets/#{subnet.id}/config",
            params: { currency: 'THB' }.to_json,
            headers: super_headers
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['config']['currency']).to eq('THB')

      get '/v1/site_config', headers: super_headers
      body = JSON.parse(response.body)
      expect(body['config']['currency']).to eq('THB')
      thb = body['available_currencies'].find { |c| c['code'] == 'THB' }
      expect(thb['name']).to eq('Thai baht')
      expect(thb['locale']).to eq('th-TH')
    end
  end

  describe 'PATCH /v1/admin/currencies/:code' do
    it 'updates name and locale for a newly registered code' do
      SupportedCurrency.create!(code: 'PHP', name: 'Philippine peso', locale: 'en-PH')

      patch '/v1/admin/currencies/PHP',
            params: { name: 'Peso', locale: 'fil-PH' }.to_json,
            headers: super_headers
      expect(response).to have_http_status(200)

      body = JSON.parse(response.body)
      expect(body['name']).to eq('Peso')
      expect(body['locale']).to eq('fil-PH')
    end

    it 'deactivates a registered code so it leaves the picker' do
      SupportedCurrency.create!(code: 'PHP', name: 'Philippine peso', locale: 'en-PH')

      patch '/v1/admin/currencies/PHP',
            params: { active: false }.to_json,
            headers: super_headers
      expect(response).to have_http_status(200)
      expect(SiteConfig.normalize_currency('PHP')).to be_nil
    end

    it 'refuses to deactivate CAD' do
      patch '/v1/admin/currencies/CAD',
            params: { active: false }.to_json,
            headers: super_headers
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to eq('Cannot deactivate the default currency')
      expect(SiteConfig.normalize_currency('CAD')).to eq('CAD')
    end

    it 'returns 404 for a code that is not registered' do
      patch '/v1/admin/currencies/XXX',
            params: { name: 'Nope' }.to_json,
            headers: super_headers
      expect(response).to have_http_status(404)
    end
  end
end
