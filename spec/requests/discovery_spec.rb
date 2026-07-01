require 'rails_helper'

# Request spec for the Local Discovery API (Api::V1::DiscoveryController).
#
# Harness modelled on the existing on-master request specs
# (spec/requests/multi_use_registration_spec.rb): real User rows via
# User.create!, HS256 bearer tokens minted by JwtGenerationService (the same
# path every controller/request spec uses — verifies via the test HS256
# bridge), skip_hooks so DatabaseCleaner/seed loading is bypassed, and a
# per-example truncation clean.
#
# The whole point of this suite is the AC 15 privacy invariant: raw
# coordinates are quantised to a fixed grid-cell centroid (Discovery::GridSnap)
# before storage, are never echoed back, and the read path derives its origin
# ONLY from the caller's stored centroid — never a client-supplied coordinate.
RSpec.describe 'Discovery API', type: :request, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  # --- helpers -------------------------------------------------------------

  # Creates a real user. FactoryBot's :user factory hardcodes user_name/email
  # (single-row only), so — like multi_use_registration_spec.rb — we build rows
  # directly with a unique handle so several can coexist in one example.
  def mk(prefix)
    User.create!(user_name: "#{prefix}#{SecureRandom.hex(4)}", password: 'bobsentme!')
  end

  # A user in the demo cohort (demo user_group → User#demo? true), matching the
  # demo-group pattern the existing specs use (user.user_groups.create!).
  def mk_demo(prefix)
    u = mk(prefix)
    u.user_groups.create!(group_label: 'demo')
    u
  end

  # Bearer header for a user. JSON content type so PATCH bodies sent as
  # `.to_json` are parsed into params.
  def auth_headers(user)
    {
      'Authorization' => "Bearer #{JwtGenerationService.new(user).token}",
      'CONTENT_TYPE' => 'application/json',
    }
  end

  # Simulates PATCH /location: store the SNAPPED centroid (never the raw point),
  # stamp location_updated_at now.
  def locate!(user, lat, lng)
    cell = Discovery::GridSnap.snap(lat, lng)
    user.update!(latitude: cell[0], longitude: cell[1], location_updated_at: Time.current)
  end

  # Simulates PATCH /settings { opted_in: true }.
  def opt_in!(user)
    user.update!(location_opted_in: true)
  end

  def body
    JSON.parse(response.body)
  end

  let(:caller)   { mk('caller') }
  let(:target)   { mk('target') }
  let(:caller_a) { mk('callera') }
  let(:caller_b) { mk('callerb') }

  # === PATCH /v1/discovery/location ======================================

  describe 'PATCH /v1/discovery/location' do
    it 'returns 401 for an unauthenticated request (AC 13)' do
      patch '/v1/discovery/location'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'stores the snapped centroid, not the raw input' do
      raw_lat, raw_lng = 45.123456789, -73.987654321
      patch '/v1/discovery/location',
        params: { latitude: raw_lat, longitude: raw_lng }.to_json,
        headers: auth_headers(caller)

      expect(response).to have_http_status(200)
      caller.reload
      expect(caller.latitude).not_to eq(raw_lat)
      expect(caller.longitude).not_to eq(raw_lng)
      cell = Discovery::GridSnap.snap(raw_lat, raw_lng)
      expect(caller.latitude.to_f).to  eq(cell[0])
      expect(caller.longitude.to_f).to eq(cell[1])
    end

    it 'responds with the stored centroid (cell_lat/cell_lng), not the raw input' do
      raw_lat, raw_lng = 45.123456789, -73.987654321
      patch '/v1/discovery/location',
        params: { latitude: raw_lat, longitude: raw_lng }.to_json,
        headers: auth_headers(caller)

      cell = Discovery::GridSnap.snap(raw_lat, raw_lng)
      expect(body['cell_lat']).to eq(cell[0])
      expect(body['cell_lng']).to eq(cell[1])
      expect(body['cell_lat']).not_to eq(raw_lat)
      expect(body['cell_lng']).not_to eq(raw_lng)
    end

    it 'does not change location_opted_in (capture is decoupled from visibility)' do
      patch '/v1/discovery/location',
        params: { latitude: 45.0, longitude: -73.0 }.to_json,
        headers: auth_headers(caller)

      caller.reload
      expect(caller.location_opted_in).to be false
    end

    it 'sets location_updated_at' do
      expect(caller.location_updated_at).to be_nil
      patch '/v1/discovery/location',
        params: { latitude: 45.0, longitude: -73.0 }.to_json,
        headers: auth_headers(caller)

      caller.reload
      expect(caller.location_updated_at).not_to be_nil
    end
  end

  # === PATCH /v1/discovery/settings ======================================

  describe 'PATCH /v1/discovery/settings' do
    it 'returns 401 for an unauthenticated request' do
      patch '/v1/discovery/settings'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'sets location_opted_in to true' do
      patch '/v1/discovery/settings',
        params: { opted_in: true }.to_json, headers: auth_headers(caller)

      expect(response).to have_http_status(200)
      caller.reload
      expect(caller.location_opted_in).to be true
    end

    it 'accepts a valid radius_km and stores it' do
      patch '/v1/discovery/settings',
        params: { radius_km: 50 }.to_json, headers: auth_headers(caller)

      expect(response).to have_http_status(200)
      caller.reload
      expect(caller.discovery_radius_km).to eq(50)
    end

    it 'returns 422 for a radius_km outside {5,10,25,50,100}' do
      patch '/v1/discovery/settings',
        params: { radius_km: 7 }.to_json, headers: auth_headers(caller)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'opt-out does NOT clear latitude/longitude (AC 11)' do
      caller.update!(latitude: 45.005, longitude: -73.005, location_updated_at: 1.day.ago)
      patch '/v1/discovery/settings',
        params: { opted_in: false }.to_json, headers: auth_headers(caller)

      caller.reload
      expect(caller.location_opted_in).to be false
      expect(caller.latitude).not_to be_nil
      expect(caller.longitude).not_to be_nil
    end
  end

  # === GET /v1/discovery/nearby ==========================================

  describe 'GET /v1/discovery/nearby' do
    it 'returns 401 for an unauthenticated request (AC 13)' do
      get '/v1/discovery/nearby'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns { origin_cell: nil, members: [] } when the caller has no stored centroid' do
      get '/v1/discovery/nearby', headers: auth_headers(caller)

      expect(response).to have_http_status(200)
      expect(body['origin_cell']).to be_nil
      expect(body['members']).to eq([])
    end

    it 'includes an opted-in, non-stale member within radius (AC 1)' do
      locate!(caller, 45.0, -73.0)
      locate!(target, 45.01, -73.01)
      opt_in!(target)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      ids = body['members'].map { |m| m['id'] }
      expect(ids).to include(target.id)
    end

    it 'excludes an opted-out member (AC 2)' do
      locate!(caller, 45.0, -73.0)
      locate!(target, 45.01, -73.01)
      opt_in!(target)
      patch '/v1/discovery/settings',
        params: { opted_in: false }.to_json, headers: auth_headers(target)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      ids = body['members'].map { |m| m['id'] }
      expect(ids).not_to include(target.id)
    end

    it 'excludes a stale member (location_updated_at past the staleness cutoff) (AC 1)' do
      locate!(caller, 45.0, -73.0)
      locate!(target, 45.01, -73.01)
      opt_in!(target)
      target.update!(location_updated_at: 40.days.ago)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      ids = body['members'].map { |m| m['id'] }
      expect(ids).not_to include(target.id)
    end

    it 'excludes a deleted user (deleted_at set) (AC 7)' do
      locate!(caller, 45.0, -73.0)
      locate!(target, 45.01, -73.01)
      opt_in!(target)
      target.update!(deleted_at: Time.current)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      ids = body['members'].map { |m| m['id'] }
      expect(ids).not_to include(target.id)
    end

    it 'excludes a disabled user (disabled_at set) (AC 7)' do
      locate!(caller, 45.0, -73.0)
      locate!(target, 45.01, -73.01)
      opt_in!(target)
      target.update!(disabled_at: Time.current)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      ids = body['members'].map { |m| m['id'] }
      expect(ids).not_to include(target.id)
    end

    it 'does NOT return a demo user for a non-demo caller (same-demo scoping)' do
      demo_target = mk_demo('demotgt')
      locate!(caller, 45.0, -73.0)          # caller is a real (non-demo) user
      locate!(demo_target, 45.01, -73.01)
      opt_in!(demo_target)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      ids = body['members'].map { |m| m['id'] }
      expect(ids).not_to include(demo_target.id)
    end

    # Regression guard for the demo-scoping query form that 500'd via an
    # accidental eager_load (fixed in the P2 controller). A demo caller with a
    # nearby opted-in demo member must get that member back — 200, member
    # present, numeric distance, non-nil role.
    it 'returns a nearby opted-in demo member to a demo caller with a numeric distance and role' do
      demo_caller = mk_demo('democaller')
      demo_target = mk_demo('demomember')
      demo_target.user_groups.create!(group_label: 'producer') # a real role so role_label is non-nil
      locate!(demo_caller, 45.0, -73.0)
      locate!(demo_target, 45.01, -73.01)
      opt_in!(demo_target)

      get '/v1/discovery/nearby', headers: auth_headers(demo_caller)

      expect(response).to have_http_status(200)
      member = body['members'].find { |m| m['id'] == demo_target.id }
      expect(member).not_to be_nil
      expect(member['distance_km']).to be_a(Numeric)
      expect(member['role']).not_to be_nil
    end

    it 'never includes the caller in their own results (self-exclusion)' do
      locate!(caller, 45.0, -73.0)
      opt_in!(caller)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      ids = body['members'].map { |m| m['id'] }
      expect(ids).not_to include(caller.id)
    end

    it 'returns a centroid-to-centroid distance_km that is >= 0' do
      locate!(caller, 45.0, -73.0)
      locate!(target, 45.01, -73.01)
      opt_in!(target)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      member = body['members'].find { |m| m['id'] == target.id }
      expect(member['distance_km']).to be >= 0
    end

    it 'orders members by distance_km ascending' do
      locate!(caller, 45.0, -73.0)
      near = mk('near'); locate!(near, 45.01, -73.01); opt_in!(near)
      far  = mk('far');  locate!(far, 45.15, -73.15);  opt_in!(far)

      get '/v1/discovery/nearby', headers: auth_headers(caller)

      distances = body['members'].map { |m| m['distance_km'] }
      expect(distances).to eq(distances.sort)
      expect(distances.length).to be >= 2
    end
  end

  # === AC 15 privacy invariant (REQUIRED — locked by the Visionary) ======

  context 'AC15a — origin from stored centroid only' do
    it 'ignores any coordinate passed in the request; uses the stored centroid' do
      locate!(caller, 45.0, -73.0)
      locate!(target, 45.005, -73.005)
      opt_in!(target)

      # GET /nearby takes no coordinate param; even a rogue client-supplied
      # coordinate must be ignored — origin comes only from the stored centroid.
      get '/v1/discovery/nearby',
        params: { latitude: 99.0, longitude: 99.0 },
        headers: auth_headers(caller)

      stored = Discovery::GridSnap.snap(45.0, -73.0)
      expect(body['origin_cell']['cell_lat'].to_f).to be_within(0.0001).of(stored[0])
      expect(body['origin_cell']['cell_lng'].to_f).to be_within(0.0001).of(stored[1])
    end

    it 'returns origin_cell: nil when the caller has no stored centroid' do
      get '/v1/discovery/nearby', headers: auth_headers(caller)

      expect(body['origin_cell']).to be_nil
      expect(body['members']).to eq([])
    end
  end

  context 'AC15b — sub-cell movement yields identical distance_km' do
    it 'distance is stable when the requester moves within the same grid cell' do
      locate!(target, 45.1, -73.1)
      opt_in!(target)

      # Two callers at different precise points inside the SAME ~1 km cell.
      locate!(caller_a, 45.0, -73.0)
      locate!(caller_b, 45.0001, -73.0001) # sub-cell movement → same snapped centroid

      caller_a.reload; caller_b.reload
      expect(caller_a.latitude).to  eq(caller_b.latitude)
      expect(caller_a.longitude).to eq(caller_b.longitude)

      get '/v1/discovery/nearby', headers: auth_headers(caller_a)
      dist_a = body['members'].first&.dig('distance_km')
      get '/v1/discovery/nearby', headers: auth_headers(caller_b)
      dist_b = body['members'].first&.dig('distance_km')

      expect(dist_a).not_to be_nil
      expect(dist_a).to eq(dist_b)
    end
  end

  context 'AC15c — write path stores only the snapped centroid' do
    it 'latitude/longitude on the user row equals the GridSnap centroid, not the raw input' do
      raw_lat, raw_lng = 45.123456789, -73.987654321
      patch '/v1/discovery/location',
        params: { latitude: raw_lat, longitude: raw_lng }.to_json,
        headers: auth_headers(caller)

      caller.reload
      snapped = Discovery::GridSnap.snap(raw_lat, raw_lng)
      expect(caller.latitude.to_f).to  eq(snapped[0])
      expect(caller.longitude.to_f).to eq(snapped[1])
      expect(caller.latitude.to_f).not_to  eq(raw_lat)
      expect(caller.longitude.to_f).not_to eq(raw_lng)
    end
  end

  context 'AC15d — single GRID_SIZE_DEG on write and query' do
    # Non-circular guard: consume snap's ACTUAL output. Assert the single
    # constant is 0.01, then measure the E-W width between two ADJACENT-longitude
    # cell centroids returned by snap at 55°N. If the longitude step were ever
    # reverted to a fixed GRID_SIZE_DEG, the measured width collapses to ~0.64 km
    # and this goes RED (mirrors spec/services/discovery/grid_snap_spec.rb test 5).
    it 'uses one GRID_SIZE_DEG == 0.01 and yields an E-W cell width >= 1 km at 55°N measured from snap output' do
      expect(Discovery::GridSnap::GRID_SIZE_DEG).to eq(0.01)

      _, cell_lng_a = Discovery::GridSnap.snap(55.0, 0.0)
      _, cell_lng_b = Discovery::GridSnap.snap(55.0, 0.019)
      ew_km = (cell_lng_b - cell_lng_a).abs * Math.cos(55.0 * Math::PI / 180.0) * 111.32

      expect(ew_km).to be >= 1.0
    end
  end
end
