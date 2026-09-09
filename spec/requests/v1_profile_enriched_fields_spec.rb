require 'rails_helper'

# Enriched profiles (Plan 30). PATCH /v1/users/profile now carries two more
# identity fields (about, area_label) that proxy to auth.foaf.io and mirror
# onto the local users row, plus one app-owned field (offering) that is written
# locally and NEVER proxied to auth. AuthFoafClient is stubbed (no real auth
# service in test).
RSpec.describe 'V1 enriched profile fields', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:user) { User.create!(user_name: 'enriched', password: password) }
  let(:headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(user).token}",
      'Content-Type' => 'application/json' }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def json
    JSON.parse(response.body)
  end

  it 'proxies about + area_label to auth and mirrors them onto the local row' do
    expect(AuthFoafClient).to receive(:update_profile)
      .with(patch: hash_including('about' => 'Grows heirloom tomatoes.', 'area_label' => 'Crawford Bay, BC'),
            bearer: kind_of(String))
      .and_return([200, { 'identity' => {
        'foaf_id' => user.foaf_id, 'user_name' => user.user_name,
        'about' => 'Grows heirloom tomatoes.', 'area_label' => 'Crawford Bay, BC'
      } }])

    patch '/v1/users/profile',
          params: { about: 'Grows heirloom tomatoes.', area_label: 'Crawford Bay, BC' }.to_json,
          headers: headers

    expect(response).to have_http_status(:ok)
    expect(json['identity']['about']).to eq('Grows heirloom tomatoes.')
    expect(user.reload.about).to eq('Grows heirloom tomatoes.')
    expect(user.reload.area_label).to eq('Crawford Bay, BC')
  end

  it 'writes offering to the local row without proxying it to auth' do
    expect(AuthFoafClient).not_to receive(:update_profile)

    patch '/v1/users/profile', params: { offering: 'Tomatoes, honey, eggs.' }.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect(user.reload.offering).to eq('Tomatoes, honey, eggs.')
  end

  it 'rejects an over-long offering (>140) with 422 and no auth call' do
    expect(AuthFoafClient).not_to receive(:update_profile)

    patch '/v1/users/profile', params: { offering: 'x' * 141 }.to_json, headers: headers

    expect(response).to have_http_status(422)
    expect(json['code']).to eq('validation_failed')
    expect(user.reload.offering).to be_nil
  end

  it 'handles a combined patch: proxies the identity field, writes offering locally' do
    expect(AuthFoafClient).to receive(:update_profile)
      .with(patch: hash_including('about' => 'Bio here.'), bearer: kind_of(String))
      .and_return([200, { 'identity' => {
        'foaf_id' => user.foaf_id, 'user_name' => user.user_name, 'about' => 'Bio here.'
      } }])

    patch '/v1/users/profile', params: { about: 'Bio here.', offering: 'Eggs.' }.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect(user.reload.about).to eq('Bio here.')
    expect(user.reload.offering).to eq('Eggs.')
  end

  it 'exposes offering in the app-owned profile payload' do
    user.update!(offering: 'Seasonal veg boxes.')

    get '/v1/profile', headers: headers

    expect(response).to have_http_status(:ok)
    expect(json['offering']).to eq('Seasonal veg boxes.')
  end
end
