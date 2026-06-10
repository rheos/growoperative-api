require 'rails_helper'

# Job 51 W4 — RegistrationsController redemption-decision lookups now use
# Invitation.find_active_by_code (was find_by_code). These pin that the
# behaviour the app depends on is unchanged:
#   * a single-use accepted code still reports "already used" (resolved via
#     the find_by_code fallback inside find_active_by_code), and
#   * when a freed-then-reissued string has both an old accepted row and a
#     new pending row, the new pending row is what the gate evaluates.
# Signup itself proxies to auth.foaf.io (globally stubbed); these assert the
# gate, not the auth round-trip.
RSpec.describe 'RegistrationsController invitation lookup (W4)', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) { User.create!(user_name: 'reg_inviter', password: password, invite_limit: 3) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def signup(code:, user_name:)
    post '/v1/signup', params: {
      user: { user_name: user_name, password: password, password_confirmation: password, invited_code: code }
    }
  end

  def parsed
    JSON.parse(response.body)
  end

  it 'still reports "already used" for a single-use accepted code (resolved via find_by_code fallback)' do
    accepted = inviter.invitations.create!(
      user_type: 'consumer', status: 1, accepted_id: inviter.id, invitation_code: 'REGUSED1'
    )

    signup(code: accepted.invitation_code, user_name: 'reg_used')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(parsed['message']).to eq('Invitation code is already used')
  end

  it 'evaluates the new pending row when a freed-then-reissued string has an older accepted row' do
    # Older terminal row for the same canonical string...
    inviter.invitations.create!(
      user_type: 'consumer', status: 1, accepted_id: inviter.id, invitation_code: 'REGREISS'
    )
    # ...then the string is reissued as a fresh pending row.
    inviter.invitations.create!(
      user_type: 'consumer', status: 0, invitation_code: 'REGREISS'
    )

    # The active-scoped lookup resolves the pending row, so signup succeeds
    # instead of incorrectly reporting "already used" from the stale terminal row.
    signup(code: 'REGREISS', user_name: 'reg_reissued')
    expect(response).to have_http_status(:created)
  end
end
