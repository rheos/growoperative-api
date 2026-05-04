require 'rails_helper'

# Job 11 acceptance (master plan §1 + §Atomic accept/onboarding recovery):
#   - POST /v1/onboarding wraps app effects in one transaction.
#   - Idempotent on (invitation, foaf_id) — retry returns same result,
#     no duplicate effects.
#   - Terminal `rejected` outcomes do NOT auto-retry; UI surface differs
#     from `pending`.
#   - GET /v1/onboarding/status returns the current onboarding row.
RSpec.describe 'v1 onboarding', type: :request do
  let(:password) { 'bobsentme!' }

  let!(:inviter) do
    User.create!(
      user_name: 'inviter_user',
      email: 'inviter@example.com',
      password: password,
      password_confirmation: password,
    )
  end

  let!(:accepter) do
    User.create!(
      user_name: 'accepter_user',
      email: 'accepter@example.com',
      password: password,
      password_confirmation: password,
    )
  end

  def auth_headers(user = accepter)
    token = JwtGenerationService.new(user).token
    { 'HTTP_AUTHORIZATION' => "Bearer #{token}", 'HTTPS' => 'on', 'CONTENT_TYPE' => 'application/json' }
  end

  def make_invitation(user: inviter, user_type: 'consumer', subnet: nil, code: 'INV12345')
    Invitation.create!(
      user: user,
      status: :pending,
      invitation_code: code,
      user_type: Invitation.user_types[user_type],
      subnet: subnet,
    )
  end

  def parsed
    JSON.parse(response.body)
  end

  describe 'POST /v1/onboarding — happy path' do
    let!(:invitation) { make_invitation }

    it 'completes onboarding and returns the v1 envelope + onboarding block' do
      post '/v1/onboarding',
        params: { invitation_code: invitation.invitation_code }.to_json,
        env: auth_headers
      expect(response).to have_http_status(:ok)
      expect(parsed['identity']['foaf_id']).to eq(accepter.foaf_id)
      expect(parsed['onboarding']['app_onboarding_status']).to eq('completed')
      expect(parsed['onboarding']['app_onboarding_completed_at']).to be_present
      invitation.reload
      expect(invitation.app_onboarding_status).to eq('completed')
      expect(invitation.accepted_id).to eq(accepter.id)
      expect(Relationship.where(
        '(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)',
        inviter.id, accepter.id, accepter.id, inviter.id,
      ).count).to eq(1)
    end
  end

  describe 'POST /v1/onboarding — idempotency' do
    let!(:invitation) { make_invitation }

    it 'returning the same result on retry without duplicate effects' do
      2.times do
        post '/v1/onboarding',
          params: { invitation_code: invitation.invitation_code }.to_json,
          env: auth_headers
        expect(response).to have_http_status(:ok)
        expect(parsed['onboarding']['app_onboarding_status']).to eq('completed')
      end
      # No duplicate user_groups, relationships, or subnet memberships.
      expect(accepter.reload.user_groups.where(group_label: 'consumer').count).to eq(1)
      expect(Relationship.where(
        '(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)',
        inviter.id, accepter.id, accepter.id, inviter.id,
      ).count).to eq(1)
    end
  end

  describe 'POST /v1/onboarding — transactional rollback' do
    let!(:invitation) { make_invitation }

    it 'rolls back user_group + relationship + invitation update if any step fails' do
      # Force the relationship-create step to blow up after user_group
      # create has already happened. The transaction must roll back the
      # user_group too — invitation must remain pending.
      allow_any_instance_of(OnboardingService).to receive(:ensure_relationship!).and_raise(StandardError, 'simulated mid-flow failure')

      post '/v1/onboarding',
        params: { invitation_code: invitation.invitation_code }.to_json,
        env: auth_headers

      expect(response).to have_http_status(:internal_server_error)
      invitation.reload
      expect(invitation.app_onboarding_status).to eq('failed')
      expect(invitation.status).to eq('pending')
      # Critical rollback assertion: no user_group survived.
      expect(accepter.reload.user_groups.where(group_label: 'consumer')).to be_empty
    end
  end

  describe 'POST /v1/onboarding — terminal rejection codes' do
    it 'rejects with role_policy_violation if accepter tries to accept their own invite' do
      own_invitation = make_invitation(user: accepter, code: 'SELFINV1')
      post '/v1/onboarding',
        params: { invitation_code: own_invitation.invitation_code }.to_json,
        env: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed['onboarding']['app_onboarding_status']).to eq('rejected')
      expect(parsed['onboarding']['app_onboarding_rejection_code']).to eq('role_policy_violation')

      own_invitation.reload
      expect(own_invitation.app_onboarding_status).to eq('rejected')
    end

    it 'does not auto-retry a previously rejected invitation' do
      own_invitation = make_invitation(user: accepter, code: 'SELFINV2')
      # Trip the rejection once.
      post '/v1/onboarding',
        params: { invitation_code: own_invitation.invitation_code }.to_json,
        env: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)

      # A second call returns the same rejection without re-evaluating
      # policy (i.e., does not "fix itself" if policy changes underneath).
      post '/v1/onboarding',
        params: { invitation_code: own_invitation.invitation_code }.to_json,
        env: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed['onboarding']['app_onboarding_rejection_code']).to eq('role_policy_violation')
    end

    it 'rejects banned_email_domain when subnet enforces email and accepter has none' do
      no_email_user = User.create!(user_name: 'no_email', password: password, password_confirmation: password)
      subnet = Subnet.create!(name: 'EmailRequired', seed_user_id: inviter.id)
      SubnetConfig.create!(subnet: subnet, version: 1, config: { 'enforce_valid_email' => true })
      invitation = make_invitation(subnet: subnet, code: 'EMAILREQ')

      token = JwtGenerationService.new(no_email_user).token
      post '/v1/onboarding',
        params: { invitation_code: invitation.invitation_code }.to_json,
        env: { 'HTTP_AUTHORIZATION' => "Bearer #{token}", 'HTTPS' => 'on', 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed['onboarding']['app_onboarding_rejection_code']).to eq('banned_email_domain')
    end
  end

  describe 'GET /v1/onboarding/status' do
    let!(:invitation) { make_invitation }

    it 'reports pending before onboarding runs' do
      get '/v1/onboarding/status', params: { invitation_code: invitation.invitation_code }, env: auth_headers
      expect(response).to have_http_status(:ok)
      expect(parsed['app_onboarding_status']).to eq('pending')
      expect(parsed['target_app']).to eq('growoperative')
    end

    it 'reports completed after a successful POST /v1/onboarding' do
      post '/v1/onboarding',
        params: { invitation_code: invitation.invitation_code }.to_json,
        env: auth_headers
      get '/v1/onboarding/status', params: { invitation_code: invitation.invitation_code }, env: auth_headers
      expect(response).to have_http_status(:ok)
      expect(parsed['app_onboarding_status']).to eq('completed')
      expect(parsed['app_onboarding_completed_at']).to be_present
    end

    it 'returns 404 for an unknown invitation code' do
      get '/v1/onboarding/status', params: { invitation_code: 'NOSUCH' }, env: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /v1/onboarding — auth' do
    it 'requires authentication' do
      invitation = make_invitation
      post '/v1/onboarding',
        params: { invitation_code: invitation.invitation_code }.to_json,
        env: { 'HTTPS' => 'on', 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects without invitation_code' do
      post '/v1/onboarding', params: '{}', env: auth_headers
      expect(response).to have_http_status(:bad_request)
    end
  end
end
