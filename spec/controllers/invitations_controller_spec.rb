require 'rails_helper'

RSpec.describe 'Invitations controller — multi-use', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:owner) { User.create!(user_name: 'ic_owner', password: password, invite_limit: 50) }
  let(:other) { User.create!(user_name: 'ic_other', password: password) }

  def auth_headers(user = owner)
    { 'Authorization' => "Bearer #{JwtGenerationService.new(user).token}" }
  end

  def parsed
    JSON.parse(response.body)
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  # Counts only the redemption-table SQL so the assertion measures the N+1
  # surface this feature adds, independent of seed/auth/serialization queries.
  def redemption_query_count
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      count += 1 if sql =~ /invitation_redemptions/i && payload[:name] != 'SCHEMA'
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
    count
  end

  describe 'GET /v1/invitations' do
    it 'emits multi_use, active, redemptions_count and redeemers for multi-use rows' do
      invitation = owner.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'ICMULTI1')
      r1 = User.create!(user_name: 'ic_r1', nickname: 'Ruby One', password: password)
      r2 = User.create!(user_name: 'ic_r2', password: password)
      invitation.invitation_redemptions.create!(user_id: r1.id, redeemed_at: Time.current)
      invitation.invitation_redemptions.create!(user_id: r2.id, redeemed_at: Time.current)

      get '/v1/invitations', headers: auth_headers
      expect(response).to have_http_status(200)

      row = parsed['data'].find { |r| r['id'] == invitation.id }
      expect(row['multi_use']).to eq(true)
      expect(row['active']).to eq(true)
      expect(row['redemptions_count']).to eq(2)
      names = row['redeemers'].map { |x| x['name'] }
      expect(names).to contain_exactly('Ruby One', 'ic_r2') # nickname preferred, else user_name
      expect(row['redeemers'].map { |x| x['user_id'] }).to contain_exactly(r1.id, r2.id)
    end

    it 'reports active false for a switched-off multi-use code' do
      owner.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'ICMULTI2', disabled_at: Time.current)
      get '/v1/invitations', headers: auth_headers
      row = parsed['data'].find { |r| r['invitation_code'] == 'ICMULTI2' }
      expect(row['active']).to eq(false)
    end

    it 'does not regress single-use rows (no multi_use enrichment keys)' do
      acceptor = User.create!(user_name: 'ic_acc', password: password)
      owner.invitations.create!(user_type: 'consumer', status: 1, accepted_id: acceptor.id, invitation_code: 'ICSINGLE')
      get '/v1/invitations', headers: auth_headers
      row = parsed['data'].find { |r| r['invitation_code'] == 'ICSINGLE' }
      expect(row).not_to have_key('redemptions_count')
      expect(row).not_to have_key('redeemers')
    end

    it 'uses a constant number of redemption queries regardless of row/redeemer count (no N+1)' do
      # Two multi-use codes, several redeemers each.
      i1 = owner.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'ICNPLUS1')
      i2 = owner.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'ICNPLUS2')
      4.times do |n|
        u = User.create!(user_name: "ic_np_#{n}", password: password)
        i1.invitation_redemptions.create!(user_id: u.id, redeemed_at: Time.current)
        i2.invitation_redemptions.create!(user_id: u.id, redeemed_at: Time.current)
      end

      count = redemption_query_count do
        get '/v1/invitations', headers: auth_headers
      end
      expect(response).to have_http_status(200)
      # Exactly the grouped-count query + the joined names pluck.
      expect(count).to eq(2)
    end
  end

  describe 'PUT /v1/invitations/:id/set_active' do
    let!(:invitation) { owner.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'ICTOGGLE') }

    it 'switches the code off then on' do
      put "/v1/invitations/#{invitation.id}/set_active", params: { active: false }, headers: auth_headers
      expect(response).to have_http_status(200)
      expect(parsed['data']['active']).to eq(false)
      expect(invitation.reload.disabled_at).to be_present

      put "/v1/invitations/#{invitation.id}/set_active", params: { active: true }, headers: auth_headers
      expect(response).to have_http_status(200)
      expect(parsed['data']['active']).to eq(true)
      expect(invitation.reload.disabled_at).to be_nil
    end

    it 'refuses to toggle a single-use code' do
      single = owner.invitations.create!(user_type: 'consumer', status: 0, invitation_code: 'ICSINGT')
      put "/v1/invitations/#{single.id}/set_active", params: { active: false }, headers: auth_headers
      expect(response).to have_http_status(422)
    end

    it 'is authorization-scoped — one user cannot toggle another user code' do
      put "/v1/invitations/#{invitation.id}/set_active", params: { active: false }, headers: auth_headers(other)
      expect(response).to have_http_status(422)
      expect(parsed['message']).to eq('You are not authorised to access.')
      expect(invitation.reload.disabled_at).to be_nil
    end
  end

  # Job 51 — set_active signals the issuance lifecycle into FOAF when the
  # bridge is on and the row has a FOAF authority id. Best-effort: a FOAF
  # failure degrades to liveness only and never raises to the caller.
  describe 'PUT /v1/invitations/:id/set_active — FOAF signal (Job 51)' do
    let!(:synced) do
      owner.invitations.create!(
        user_type: 'consumer', status: 0, multi_use: true,
        invitation_code: 'ICFOAF1', auth_invitation_id: 'foaf-inv-1'
      )
    end

    def with_bridge(on)
      prior = ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED']
      ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = on ? 'true' : nil
      yield
    ensure
      ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = prior
    end

    it 'calls AuthFoafClient.disable_invitation with the stored auth_invitation_id on disable' do
      with_bridge(true) do
        expect(AuthFoafClient).to receive(:disable_invitation).with(invitation_id: 'foaf-inv-1').and_return({})

        put "/v1/invitations/#{synced.id}/set_active", params: { active: false }, headers: auth_headers
        expect(response).to have_http_status(200)
      end
      expect(synced.reload.disabled_at).to be_present
    end

    it 'calls AuthFoafClient.enable_invitation on re-enable' do
      synced.update!(disabled_at: Time.current)
      with_bridge(true) do
        expect(AuthFoafClient).to receive(:enable_invitation).with(hash_including(invitation_id: 'foaf-inv-1')).and_return({})

        put "/v1/invitations/#{synced.id}/set_active", params: { active: true }, headers: auth_headers
        expect(response).to have_http_status(200)
      end
      expect(synced.reload.disabled_at).to be_nil
    end

    it 'does not raise to the caller when the FOAF disable signal fails' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:disable_invitation).and_raise(AuthFoafClient::Error.new(status: 500, body: {}))

        put "/v1/invitations/#{synced.id}/set_active", params: { active: false }, headers: auth_headers
        expect(response).to have_http_status(200)
        expect(parsed['data']['active']).to eq(false)
      end
      # The local toggle still succeeded — liveness degraded, not correctness.
      expect(synced.reload.disabled_at).to be_present
    end

    it 'does not signal FOAF when the bridge is off' do
      with_bridge(false) do
        expect(AuthFoafClient).not_to receive(:disable_invitation)
        put "/v1/invitations/#{synced.id}/set_active", params: { active: false }, headers: auth_headers
        expect(response).to have_http_status(200)
      end
    end

    it 'does not signal FOAF when the row has no auth_invitation_id' do
      local_only = owner.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'ICNOAUTH')
      with_bridge(true) do
        expect(AuthFoafClient).not_to receive(:disable_invitation)
        put "/v1/invitations/#{local_only.id}/set_active", params: { active: false }, headers: auth_headers
        expect(response).to have_http_status(200)
      end
    end
  end
end
