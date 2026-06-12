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

  describe 'GET /v1/users/generate_invitation' do
    it 'creates a multi-use invitation with a chosen easy code and label' do
      get '/v1/users/generate_invitation',
          params: { user_type: 'consumer', multi_use: true, invitation_code: 'food-24', label: 'Saturday market' },
          headers: auth_headers

      expect(response).to have_http_status(200)
      expect(parsed['invitation_code']).to eq('FOOD24')
      expect(parsed['multi_use']).to eq(true)
      expect(parsed['label']).to eq('Saturday market')
      expect(owner.invitations.find_by(invitation_code: 'FOOD24')).to be_present
    end

    it 'rejects a chosen code that is already active' do
      owner.invitations.create!(
        user_type: 'consumer',
        status: 0,
        multi_use: true,
        invitation_code: 'FOOD24',
      )

      get '/v1/users/generate_invitation',
          params: { user_type: 'consumer', multi_use: true, invitation_code: 'food 24' },
          headers: auth_headers

      expect(response).to have_http_status(422)
      expect(parsed['message']).to eq('Invitation code is already active')
    end

    it 'allows a chosen code to be reused after the old invitation is inactive' do
      owner.invitations.create!(
        user_type: 'consumer',
        status: 0,
        multi_use: true,
        invitation_code: 'FOOD24',
        disabled_at: Time.current,
      )

      get '/v1/users/generate_invitation',
          params: { user_type: 'consumer', multi_use: true, invitation_code: 'food 24' },
          headers: auth_headers

      expect(response).to have_http_status(200)
      expect(parsed['invitation_code']).to eq('FOOD24')
      expect(owner.invitations.where(invitation_code: 'FOOD24').count).to eq(2)
    end

    it 'allows multi-use generation even when normal pending slots are full' do
      limited = User.create!(user_name: 'ic_limited', password: password, invite_limit: 1)
      limited.invitations.create!(user_type: 'consumer', status: 0, invitation_code: 'FULLSLOT')
      expect(limited.ramaining_invitation_limit).to eq(0)

      get '/v1/users/generate_invitation',
          params: { user_type: 'consumer', multi_use: true, invitation_code: 'wide-open' },
          headers: auth_headers(limited)

      expect(response).to have_http_status(200)
      expect(parsed['invitation_code']).to eq('WIDEOPEN')
      expect(parsed['multi_use']).to eq(true)
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

    it 'refuses to reactivate when another active invitation reused the code' do
      put "/v1/invitations/#{invitation.id}/set_active", params: { active: false }, headers: auth_headers
      expect(response).to have_http_status(200)
      owner.invitations.create!(
        user_type: 'consumer',
        status: 0,
        multi_use: true,
        invitation_code: invitation.invitation_code,
      )

      put "/v1/invitations/#{invitation.id}/set_active", params: { active: true }, headers: auth_headers

      expect(response).to have_http_status(422)
      expect(parsed['message']).to eq('Invitation code is already active')
      expect(invitation.reload.disabled_at).to be_present
    end
  end

  describe 'POST /v1/users/accept_invitation' do
    it 'records logged-in multi-use redemptions without consuming the code' do
      invitation = owner.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'ICACCEPT')
      redeemer = User.create!(user_name: 'ic_logged_in', password: password)

      post '/v1/users/accept_invitation',
           params: { invited_code: invitation.invitation_code },
           headers: auth_headers(redeemer)

      expect(response).to have_http_status(200)
      expect(invitation.reload.status).to eq('pending')
      expect(invitation.accepted_id).to be_nil
      expect(invitation.invitation_redemptions.where(user_id: redeemer.id).count).to eq(1)
      expect(redeemer.user_groups.where(group_label: 'consumer').count).to eq(1)
    end

    it 'rejects logged-in acceptance when a multi-use code is off' do
      invitation = owner.invitations.create!(
        user_type: 'consumer',
        status: 0,
        multi_use: true,
        invitation_code: 'ICOFFAC',
        disabled_at: Time.current,
      )
      redeemer = User.create!(user_name: 'ic_logged_off', password: password)

      post '/v1/users/accept_invitation',
           params: { invited_code: invitation.invitation_code },
           headers: auth_headers(redeemer)

      expect(response).to have_http_status(422)
      expect(parsed['message']).to eq('This invitation code is no longer active')
      expect(invitation.reload.invitation_redemptions.count).to eq(0)
    end
  end
end
