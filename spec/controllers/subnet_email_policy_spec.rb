require 'rails_helper'

RSpec.describe 'Subnet email policy on signup', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def build_subnet_with_email_policy!(enforce:)
    inviter = User.create!(user_name: 'sep_inviter', password: password, invite_limit: 5)
    subnet = Subnet.create!(name: 'Email Gate', seed_user_id: inviter.id)
    SubnetConfig.create!(
      subnet: subnet, version: 1,
      config: { enforce_valid_email: enforce }
    )
    inviter.subnet_memberships.create!(subnet: subnet, is_primary: true)
    invitation = inviter.invitations.create!(
      user_type: 'broker', status: 0, subnet_id: subnet.id
    )
    [subnet, invitation]
  end

  it 'rejects email-less signup when subnet enforces email' do
    _subnet, invitation = build_subnet_with_email_policy!(enforce: true)

    post '/v1/signup', params: {
      user_name: 'sep_user', password: password, password_confirmation: password,
      invited_code: invitation.invitation_code
    }.to_json, headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(422)
    expect(JSON.parse(response.body)['message']).to match(/valid email/i)
  end

  it 'rejects malformed email when subnet enforces email' do
    _subnet, invitation = build_subnet_with_email_policy!(enforce: true)

    post '/v1/signup', params: {
      user_name: 'sep_user', password: password, password_confirmation: password,
      email: 'not-an-email', invited_code: invitation.invitation_code
    }.to_json, headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(422)
  end

  it 'accepts valid email when subnet enforces email' do
    _subnet, invitation = build_subnet_with_email_policy!(enforce: true)

    post '/v1/signup', params: {
      user_name: 'sep_user', password: password, password_confirmation: password,
      email: 'ok@example.com', invited_code: invitation.invitation_code
    }.to_json, headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(201)
  end

  it 'accepts email-less signup when subnet does NOT enforce email' do
    _subnet, invitation = build_subnet_with_email_policy!(enforce: false)

    post '/v1/signup', params: {
      user_name: 'sep_user', password: password, password_confirmation: password,
      invited_code: invitation.invitation_code
    }.to_json, headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(201)
  end
end
