require 'rails_helper'

RSpec.describe 'Seed invitations', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:superuser) do
    u = User.create!(user_name: 'si_super', password: password)
    u.user_groups.create!(group_label: 'superuser')
    u
  end
  let(:regular) { User.create!(user_name: 'si_reg', password: password) }
  let(:super_headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(superuser).token}",
      'Content-Type' => 'application/json' }
  end
  let(:reg_headers) do
    { 'Authorization' => "Bearer #{JwtGenerationService.new(regular).token}",
      'Content-Type' => 'application/json' }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'POST /v1/admin/invitations/seed' do
    it 'requires superuser' do
      post '/v1/admin/invitations/seed',
           params: { subnet_name: 'Nope' }.to_json,
           headers: reg_headers
      expect(response).to have_http_status(403)
    end

    it 'requires subnet_name' do
      post '/v1/admin/invitations/seed',
           params: { chain_limit: 5 }.to_json,
           headers: super_headers
      expect(response).to have_http_status(422)
    end

    it 'uses the pronounceable code from auth.foaf.io when available' do
      superuser.update!(foaf_id: SecureRandom.uuid)
      allow(AuthFoafClient).to receive(:create_invitation)
        .and_return([201, { 'code' => 'mavo-leni' }])

      post '/v1/admin/invitations/seed',
           params: { subnet_name: 'Kaslo Network' }.to_json,
           headers: super_headers

      expect(response).to have_http_status(201)
      body = JSON.parse(response.body)
      # find_by_code canonicalises (strips hyphen, uppercases) — assert the
      # canonical form is stored so seed codes match the normal-invite shape.
      expect(body['invitation_code']).to eq('MAVOLENI')
    end

    it 'falls back to the local random code when auth.foaf.io fails' do
      superuser.update!(foaf_id: SecureRandom.uuid)
      allow(AuthFoafClient).to receive(:create_invitation).and_raise(StandardError, 'boom')

      post '/v1/admin/invitations/seed',
           params: { subnet_name: 'Kaslo Network' }.to_json,
           headers: super_headers

      expect(response).to have_http_status(201)
      body = JSON.parse(response.body)
      expect(body['invitation_code']).to be_present
      expect(body['invitation_code'].length).to be_between(6, 8).inclusive
      expect(Invitation.easy_code?(body['invitation_code'])).to eq(true)
    end

    it 'persists subnet_seed_config with whitelisted flags and returns the code' do
      post '/v1/admin/invitations/seed',
           params: {
             subnet_name: 'Kaslo Network',
             user_type: 'broker',
             chain_limit: 5,
             default_markup: 10,
             default_markup_type: 'percent',
             visible_roles: ['broker'],
             multi_role: false,
             currency: 'EUR',
             evil_key: 'mwahaha'
           }.to_json,
           headers: super_headers
      expect(response).to have_http_status(201)

      body = JSON.parse(response.body)
      expect(body['invitation_code']).to be_present
      expect(body['inviter_user_name']).to eq('si_super')
      expect(body['subnet_seed_config']['subnet_name']).to eq('Kaslo Network')

      stored = Invitation.find(body['id']).subnet_seed_config
      expect(stored['subnet_name']).to eq('Kaslo Network')
      expect(stored['config']).to include(
        'chain_limit' => 5,
        'default_markup' => 10.0,
        'default_markup_type' => 'percent',
        'visible_roles' => ['broker'],
        'multi_role' => false,
        'currency' => 'EUR'
      )
      expect(stored['config']).not_to have_key('evil_key')
    end
  end

  describe 'redemption' do
    let(:invitation) do
      superuser.invitations.create!(
        status: 0,
        user_type: 'broker',
        subnet_seed_config: {
          'subnet_name' => 'Kaslo Network',
          'config' => {
            'chain_limit' => 5,
            'default_markup' => 10.0,
            'default_markup_type' => 'percent',
            'visible_roles' => ['broker'],
            'multi_role' => false,
            'currency' => 'EUR'
          }
        }
      )
    end

    it 'mints a new Subnet with the redeemer as seed_user' do
      new_user = User.create!(
        user_name: 'si_seed_new', password: password,
        invited_code: invitation.invitation_code
      )

      membership = new_user.subnet_memberships.first
      expect(membership).to be_present
      expect(membership.is_primary).to eq(true)
      expect(membership.joined_via_invitation_id).to eq(invitation.id)

      subnet = membership.subnet
      expect(subnet.name).to eq('Kaslo Network')
      expect(subnet.seed_user_id).to eq(new_user.id)

      config = subnet.current_config
      expect(config.version).to eq(1)
      expect(config.changed_by_user_id).to eq(new_user.id)
      expect(config.config).to include(
        'chain_limit' => 5,
        'default_markup' => 10.0,
        'default_markup_type' => 'percent',
        'visible_roles' => ['broker'],
        'multi_role' => false,
        'currency' => 'EUR'
      )
    end

    it 'keeps the inviter as parent_id (invite-tree separate from subnet)' do
      new_user = User.create!(
        user_name: 'si_seed_parent', password: password,
        invited_code: invitation.invitation_code
      )
      expect(new_user.parent_id).to eq(superuser.id)
    end

    it 'does not also enrol the redeemer in the inviter\'s subnet when subnet_id is present too' do
      inviter_subnet = create(:subnet, seed_user: superuser, name: 'Inviter Net')
      invitation.update!(subnet_id: inviter_subnet.id)

      new_user = User.create!(
        user_name: 'si_seed_only', password: password,
        invited_code: invitation.invitation_code
      )

      memberships = new_user.subnet_memberships.reload
      expect(memberships.count).to eq(1)
      expect(memberships.first.subnet.name).to eq('Kaslo Network')
    end

    it 'falls back to "{user_name}\'s Network" when subnet_name is blank' do
      invitation.update_columns(
        subnet_seed_config: { 'subnet_name' => '', 'config' => {} }
      )

      new_user = User.create!(
        user_name: 'si_fallback', password: password,
        invited_code: invitation.invitation_code
      )

      expect(new_user.subnet_memberships.first.subnet.name).to eq("si_fallback's Network")
    end

    it 'still uses the normal subnet_id path when no subnet_seed_config is set' do
      other_subnet = create(:subnet, seed_user: superuser, name: 'Ordinary')
      ordinary = superuser.invitations.create!(
        status: 0, user_type: 'consumer', subnet_id: other_subnet.id
      )

      new_user = User.create!(
        user_name: 'si_ordinary', password: password,
        invited_code: ordinary.invitation_code
      )

      membership = new_user.subnet_memberships.first
      expect(membership.subnet_id).to eq(other_subnet.id)
    end
  end
end
