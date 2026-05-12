require 'rails_helper'

RSpec.describe 'Subnet applications API', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:superuser) do
    u = User.create!(user_name: 'sa_app_super', password: password)
    u.user_groups.create!(group_label: 'superuser')
    u
  end
  let(:regular) { User.create!(user_name: 'sa_app_reg', password: password) }
  let(:super_headers) { { 'Authorization' => "Bearer #{JwtGenerationService.new(superuser).token}" } }
  let(:reg_headers)   { { 'Authorization' => "Bearer #{JwtGenerationService.new(regular).token}" } }
  let(:json_headers)  { { 'Content-Type' => 'application/json' } }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'POST /v1/subnet_applications' do
    let(:valid_params) do
      {
        community_name: 'Kootenay Lake Food Network',
        location:       'Kaslo, BC',
        contact_name:   'Franz Jansen',
        contact_email:  'franz@example.com',
        description:    'Already trading eggs for bread; want to formalize.'
      }
    end

    it 'creates an application without auth' do
      expect {
        post '/v1/subnet_applications', params: valid_params.to_json, headers: json_headers
      }.to change(SubnetApplication, :count).by(1)
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body['status']).to eq('pending')
      expect(body['id']).to be_present

      app = SubnetApplication.last
      expect(app.community_name).to eq('Kootenay Lake Food Network')
      expect(app.location).to eq('Kaslo, BC')
      expect(app.contact_name).to eq('Franz Jansen')
      expect(app.contact_email).to eq('franz@example.com')
      expect(app.status).to eq('pending')
    end

    it 'returns 422 on missing required fields' do
      post '/v1/subnet_applications',
           params: valid_params.merge(location: '').to_json,
           headers: json_headers
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['errors']).to include(match(/Location/))
    end

    it 'returns 422 on invalid email' do
      post '/v1/subnet_applications',
           params: valid_params.merge(contact_email: 'not-an-email').to_json,
           headers: json_headers
      expect(response).to have_http_status(422)
    end

    it 'ignores client-supplied status (always starts pending)' do
      post '/v1/subnet_applications',
           params: valid_params.merge(status: 'approved').to_json,
           headers: json_headers
      expect(response).to have_http_status(:created)
      expect(SubnetApplication.last.status).to eq('pending')
    end
  end

  describe 'GET /v1/subnet_applications' do
    it 'requires superuser' do
      get '/v1/subnet_applications', headers: reg_headers
      expect(response).to have_http_status(403)
    end

    it 'lists newest-first' do
      old = create(:subnet_application, community_name: 'Old', created_at: 2.days.ago)
      new = create(:subnet_application, community_name: 'New', created_at: 1.minute.ago)
      get '/v1/subnet_applications', headers: super_headers
      expect(response).to have_http_status(200)
      ids = JSON.parse(response.body)['subnet_applications'].map { |a| a['id'] }
      expect(ids.first(2)).to eq([new.id, old.id])
    end

    it 'filters by status' do
      create(:subnet_application, status: 'pending', community_name: 'P1')
      create(:subnet_application, status: 'approved', community_name: 'A1')
      get '/v1/subnet_applications', params: { status: 'approved' }, headers: super_headers
      names = JSON.parse(response.body)['subnet_applications'].map { |a| a['community_name'] }
      expect(names).to eq(['A1'])
    end
  end

  describe 'PATCH /v1/subnet_applications/:id' do
    it 'requires superuser' do
      app = create(:subnet_application)
      patch "/v1/subnet_applications/#{app.id}",
            params: { status: 'approved' }.to_json,
            headers: reg_headers.merge(json_headers)
      expect(response).to have_http_status(403)
    end

    it 'stamps reviewer + timestamp on transition' do
      app = create(:subnet_application, status: 'pending')
      patch "/v1/subnet_applications/#{app.id}",
            params: { status: 'approved' }.to_json,
            headers: super_headers.merge(json_headers)
      expect(response).to have_http_status(200)
      app.reload
      expect(app.status).to eq('approved')
      expect(app.reviewed_by_user_id).to eq(superuser.id)
      expect(app.reviewed_at).to be_present
    end

    it 'rejects unknown status values' do
      app = create(:subnet_application)
      patch "/v1/subnet_applications/#{app.id}",
            params: { status: 'mwahaha' }.to_json,
            headers: super_headers.merge(json_headers)
      expect(response).to have_http_status(422)
    end

    it 'records linked subnet id' do
      app = create(:subnet_application)
      subnet = create(:subnet)
      patch "/v1/subnet_applications/#{app.id}",
            params: { status: 'approved', created_subnet_id: subnet.id }.to_json,
            headers: super_headers.merge(json_headers)
      expect(response).to have_http_status(200)
      expect(app.reload.created_subnet_id).to eq(subnet.id)
    end
  end
end
