require 'rails_helper'

# Multi-use behaviour of OnboardingService. The single-use contract is
# already covered by spec/controllers/v1_onboarding_spec.rb; this focuses
# on the multi-use branch: redemption-keyed idempotency, status stays
# pending, and the relationship + subnet policy still get enforced.
RSpec.describe OnboardingService, type: :service, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) { User.create!(user_name: 'os_inviter', email: 'os_inviter@example.com', password: password) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def make_multi_use(code:, subnet: nil, user_type: 'consumer')
    inviter.invitations.create!(
      user_type: user_type, status: 0, multi_use: true, invitation_code: code, subnet: subnet,
    )
  end

  def relationship_between(a, b)
    Relationship.where(
      '(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)',
      a.id, b.id, b.id, a.id,
    )
  end

  describe 'happy path' do
    it 'records a redemption, leaves status pending, builds the relationship' do
      invitation = make_multi_use(code: 'OSMULTI1')
      accepter = User.create!(user_name: 'os_accepter1', email: 'a1@example.com', password: password)

      result = OnboardingService.new(user: accepter, invitation_code: invitation.invitation_code).call

      expect(result.completed?).to eq(true)
      invitation.reload
      expect(invitation.status).to eq('pending')
      expect(invitation.accepted_id).to be_nil
      expect(invitation.app_onboarding_status).to eq('pending')
      expect(invitation.invitation_redemptions.where(user_id: accepter.id).count).to eq(1)
      expect(accepter.user_groups.where(group_label: 'consumer').count).to eq(1)
      expect(relationship_between(inviter, accepter).count).to eq(1)
    end
  end

  describe 'idempotency keyed on redemption existence' do
    it 'returns completed on retry without a duplicate redemption or effects' do
      invitation = make_multi_use(code: 'OSMULTI2')
      accepter = User.create!(user_name: 'os_accepter2', email: 'a2@example.com', password: password)

      2.times do
        result = OnboardingService.new(user: accepter, invitation_code: invitation.invitation_code).call
        expect(result.completed?).to eq(true)
      end

      invitation.reload
      expect(invitation.status).to eq('pending')
      expect(invitation.invitation_redemptions.where(user_id: accepter.id).count).to eq(1)
      expect(accepter.user_groups.where(group_label: 'consumer').count).to eq(1)
      expect(relationship_between(inviter, accepter).count).to eq(1)
    end

    it 'records distinct redemptions for distinct redeemers; code stays pending' do
      invitation = make_multi_use(code: 'OSMULTI3')
      a1 = User.create!(user_name: 'os_a1', email: 'd1@example.com', password: password)
      a2 = User.create!(user_name: 'os_a2', email: 'd2@example.com', password: password)

      OnboardingService.new(user: a1, invitation_code: invitation.invitation_code).call
      OnboardingService.new(user: a2, invitation_code: invitation.invitation_code).call

      invitation.reload
      expect(invitation.status).to eq('pending')
      expect(invitation.invitation_redemptions.count).to eq(2)
      expect(invitation.redeemers).to contain_exactly(a1, a2)
    end
  end

  describe 'subnet policy still enforced' do
    it 'rejects banned_email_domain when subnet enforces email and accepter has none' do
      subnet = Subnet.create!(name: 'OSEmailReq', seed_user_id: inviter.id)
      SubnetConfig.create!(subnet: subnet, version: 1, config: { 'enforce_valid_email' => true })
      invitation = make_multi_use(code: 'OSMULTI4', subnet: subnet)
      no_email = User.create!(user_name: 'os_no_email', password: password)

      result = OnboardingService.new(user: no_email, invitation_code: invitation.invitation_code).call

      expect(result.rejected?).to eq(true)
      expect(result.rejection_code).to eq('banned_email_domain')
      expect(invitation.reload.invitation_redemptions.count).to eq(0)
    end
  end

  describe 'self-redeem guard' do
    it 'refuses when the creator tries to redeem their own multi-use code' do
      invitation = make_multi_use(code: 'OSMULTI5')
      result = OnboardingService.new(user: inviter, invitation_code: invitation.invitation_code).call
      expect(result.rejected?).to eq(true)
      expect(result.rejection_code).to eq('role_policy_violation')
    end
  end

  describe 'active/off guard' do
    it 'fails without recording redemption when a multi-use code is off' do
      invitation = make_multi_use(code: 'OSMULTI6')
      invitation.update!(disabled_at: Time.current)
      accepter = User.create!(user_name: 'os_off', email: 'off@example.com', password: password)

      result = OnboardingService.new(user: accepter, invitation_code: invitation.invitation_code).call

      expect(result.failed?).to eq(true)
      expect(result.error_message).to eq('This invitation code is no longer active')
      expect(invitation.reload.invitation_redemptions.count).to eq(0)
      expect(accepter.user_groups.where(group_label: 'consumer')).to be_empty
    end
  end
end
