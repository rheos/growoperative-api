require 'rails_helper'

# RegistrationsController#invitation_limit multi-use branch. Signup itself
# proxies to auth.foaf.io (globally stubbed); these assert the gate, not the
# auth round-trip. A multi-use code: never reports "already used", is rejected
# only when switched off, and is not constrained by the inviter's pending-slot
# limit.
RSpec.describe 'Multi-use invitation registration', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) { User.create!(user_name: 'mur_inviter', password: password, invite_limit: 1) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def make_multi_use(code:, disabled: false)
    inviter.invitations.create!(
      user_type: 'consumer', status: 0, multi_use: true, invitation_code: code,
      disabled_at: disabled ? Time.current : nil,
    )
  end

  def signup(code:, user_name:)
    post '/v1/signup', params: {
      user: { user_name: user_name, password: password, password_confirmation: password, invited_code: code }
    }
  end

  def parsed
    JSON.parse(response.body)
  end

  it 'lets many users register with the same multi-use code (no "already used")' do
    invitation = make_multi_use(code: 'MURMUL01')

    signup(code: invitation.invitation_code, user_name: 'mur_one')
    expect(response).to have_http_status(:created)

    signup(code: invitation.invitation_code, user_name: 'mur_two')
    expect(response).to have_http_status(:created)

    invitation.reload
    expect(invitation.status).to eq('pending')
    expect(invitation.invitation_redemptions.count).to eq(2)
  end

  it 'rejects registration when the code is switched off' do
    invitation = make_multi_use(code: 'MURMUL02', disabled: true)

    signup(code: invitation.invitation_code, user_name: 'mur_off')
    expect(response).to have_http_status(:unprocessable_content)
    expect(parsed['message']).to eq('This invitation code is no longer active')
  end

  it 'is not limited by the inviter pending-slot count' do
    # Consume the inviter's only pending slot with a separate single-use code,
    # then confirm the multi-use code still admits a redeemer.
    inviter.invitations.create!(user_type: 'consumer', status: 0, invitation_code: 'MURPEND1')
    expect(inviter.ramaining_invitation_limit).to be <= 0

    invitation = make_multi_use(code: 'MURMUL03')
    signup(code: invitation.invitation_code, user_name: 'mur_unbounded')
    expect(response).to have_http_status(:created)
  end

  it 'still reports "already used" for a single-use code (unchanged)' do
    invitation = inviter.invitations.create!(
      user_type: 'consumer', status: 1, accepted_id: inviter.id, invitation_code: 'MURSING1',
    )
    signup(code: invitation.invitation_code, user_name: 'mur_single')
    expect(response).to have_http_status(:unprocessable_content)
    expect(parsed['message']).to eq('Invitation code is already used')
  end
end
