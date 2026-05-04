require 'rails_helper'

RSpec.describe 'Invitation role policy', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) { User.create!(user_name: 'irp_inviter', password: password) }
  let(:auth_headers) { { 'Authorization' => "Bearer #{JwtGenerationService.new(inviter).token}" } }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def attach_subnet!(user, multi_role:, visible_roles:)
    subnet = Subnet.create!(name: 'Test Subnet', seed_user_id: user.id)
    SubnetConfig.create!(
      subnet: subnet, version: 1,
      config: { multi_role: multi_role, visible_roles: visible_roles }
    )
    user.subnet_memberships.create!(subnet: subnet, is_primary: true)
    subnet
  end

  it 'clamps invitation.user_type to visible_roles.first when multi_role is false' do
    attach_subnet!(inviter, multi_role: false, visible_roles: ['broker'])

    get '/v1/users/generate_invitation', params: { user_type: 'retailer' }, headers: auth_headers
    expect(response).to have_http_status(200)

    inv = Invitation.order(created_at: :desc).first
    expect(inv.user_type).to eq('broker')
  end

  it 'preserves invitation.user_type when multi_role is true' do
    attach_subnet!(inviter, multi_role: true, visible_roles: %w[producer broker retailer consumer])

    get '/v1/users/generate_invitation', params: { user_type: 'retailer' }, headers: auth_headers
    expect(response).to have_http_status(200)

    inv = Invitation.order(created_at: :desc).first
    expect(inv.user_type).to eq('retailer')
  end

  it 'preserves client-requested user_type when inviter has no subnet membership' do
    get '/v1/users/generate_invitation', params: { user_type: 'producer' }, headers: auth_headers
    expect(response).to have_http_status(200)

    inv = Invitation.order(created_at: :desc).first
    expect(inv.user_type).to eq('producer')
  end
end
