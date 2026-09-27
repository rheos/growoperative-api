require 'rails_helper'
require 'securerandom'

# The debug endpoints returned real user data (usernames, who traded with whom,
# item names, prices, timestamps) to unauthenticated callers on production for
# five months. The only gate was a GlobalSetting row, and a data row is not a
# permission: flipping it back to 1 re-opened everything.
#
# These examples pin the gate that survives that mistake — an admin is required
# regardless of what the setting says. The controller deliberately leaves
# development and test open (the `debug-api` skill calls it without a token), so
# every example here pretends to be a deployed environment.
RSpec.describe 'Debug API access control', type: :request, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  before(:each) do
    allow(Rails.env).to receive(:local?).and_return(false)
    enable_debug_api!(1)
  end

  def enable_debug_api!(value)
    setting = GlobalSetting.find_or_initialize_by(setting: 'debug_api_enabled')
    setting.value = value
    setting.save!(validate: false)
  end

  def mk(prefix)
    suffix = SecureRandom.hex(4)
    create(:user, user_name: "#{prefix}_#{suffix}", email: "#{prefix}_#{suffix}@test.com")
  end

  def auth_headers(user)
    {
      'Authorization' => "Bearer #{JwtGenerationService.new(user).token}",
      'Content-Type' => 'application/json'
    }
  end

  # 401 rather than 403: authenticate! runs first and the caller has no
  # identity at all. The point is that the data is not served.
  it 'refuses an unauthenticated caller even when debug_api_enabled is 1' do
    get '/v1/debug/invariants'

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses an authenticated non-admin' do
    get '/v1/debug/invariants', headers: auth_headers(mk('plain'))

    expect(response).to have_http_status(:forbidden)
  end

  it 'allows an admin' do
    admin = mk('admin')
    admin.user_groups.create!(group_label: :admin)

    get '/v1/debug/invariants', headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
  end

  it 'allows a superuser' do
    su = mk('su')
    su.user_groups.create!(group_label: :superuser)

    get '/v1/debug/invariants', headers: auth_headers(su)

    expect(response).to have_http_status(:ok)
  end

  # The setting is kept as a kill switch. It is now the weaker of the two
  # gates rather than the only one.
  it 'still refuses an admin when debug_api_enabled is 0' do
    admin = mk('admin')
    admin.user_groups.create!(group_label: :admin)
    enable_debug_api!(0)

    get '/v1/debug/invariants', headers: auth_headers(admin)

    expect(response).to have_http_status(:forbidden)
  end

  it 'leaks nothing in the refusal body' do
    get '/v1/debug/requests'

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to match(/item_request_id|user_name|price/)
  end
end
