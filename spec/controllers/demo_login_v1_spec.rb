require 'rails_helper'

# Job 14 acceptance: demo login round-trips through `FoafAuthClient`
# exactly like real login. That means the issued token carries the
# v1 claims (sub = foaf_id, aud = growoperative, legacy_uid, jti) and
# the response envelope is the bridge superset (legacy `data` block
# plus top-level `token` and `identity`). No demo-only verifier path.
RSpec.describe 'POST /v1/demo/login (v1 envelope)', type: :request do
  let!(:demo_user) do
    user = User.create!(
      user_name: 'demo_alpha',
      email: 'demo_alpha@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
    user.user_groups.create!(group_label: 'demo')
    user
  end

  let!(:non_demo_user) do
    User.create!(
      user_name: 'real_user',
      email: 'real@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
  end

  it 'returns 200 with v1 envelope (data + token + identity) for a demo user' do
    post '/v1/demo/login', params: { user_id: demo_user.id }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to have_key('data')
    expect(body).to have_key('token')
    expect(body).to have_key('identity')
    expect(body.dig('data', 'attributes', 'user_name')).to eq('demo_alpha')
    expect(body.dig('identity', 'foaf_id')).to eq(demo_user.foaf_id)
  end

  it 'issues a v1-shaped JWT with sub = foaf_id and aud = growoperative' do
    post '/v1/demo/login', params: { user_id: demo_user.id }
    token = JSON.parse(response.body)['token']
    decoded = JWT.decode(token, ENV['SECRET_KEY_BASE'], true, { algorithm: 'HS256' }).first
    expect(decoded['sub']).to eq(demo_user.foaf_id)
    expect(decoded['aud']).to eq('growoperative')
    expect(decoded['legacy_uid']).to eq(demo_user.id)
    expect(decoded['user_name']).to eq('demo_alpha')
    expect(decoded['jti']).to be_present
  end

  it 'sets the SameSite=Lax JWT cookie alongside the body token' do
    # Secure cookies require HTTPS; without this header the cookie is dropped.
    post '/v1/demo/login', params: { user_id: demo_user.id }, env: { 'HTTPS' => 'on' }
    raw = response.headers['Set-Cookie']
    cookie_lines = raw.is_a?(Array) ? raw : raw.to_s.split("\n")
    jwt_line = cookie_lines.find { |h| h.start_with?('jwt=') }
    expect(jwt_line).to be_present, "jwt cookie not set. Raw Set-Cookie: #{raw.inspect}"
    expect(jwt_line).to match(/;\s*SameSite=Lax/i)
  end

  it '404s a non-demo user (demo login does not bypass the demo group check)' do
    post '/v1/demo/login', params: { user_id: non_demo_user.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'authenticates subsequent requests with the demo bearer token' do
    post '/v1/demo/login', params: { user_id: demo_user.id }
    token = JSON.parse(response.body)['token']
    get '/v1/sessions',
      env: { 'HTTPS' => 'on', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
  end

end
