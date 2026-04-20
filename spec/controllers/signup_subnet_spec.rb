require 'rails_helper'

RSpec.describe 'Signup subnet wiring', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) { User.create!(user_name: 'su_inviter', password: password) }
  let(:subnet) { create(:subnet, seed_user: inviter) }

  before do
    inviter.subnet_memberships.create!(subnet: subnet, is_primary: true)
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'invitation generation' do
    let(:token) { "Bearer #{JwtGenerationService.new(user_id: inviter.id).token}" }

    it 'inherits the inviter primary subnet' do
      get '/v1/users/generate_invitation', params: { user_type: 'consumer' },
          headers: { 'Authorization' => token }
      expect(response).to have_http_status(200)

      invitation = Invitation.order(created_at: :desc).first
      expect(invitation.subnet_id).to eq(subnet.id)
    end
  end

  describe 'new user on signup' do
    it 'lands in the subnet carried by the invitation' do
      invitation = inviter.invitations.create!(
        user_type: 'consumer', status: 0, subnet_id: subnet.id
      )

      new_user = User.create!(
        user_name: 'su_newbie', password: password, invited_code: invitation.invitation_code
      )

      membership = new_user.subnet_memberships.first
      expect(membership).to be_present
      expect(membership.subnet_id).to eq(subnet.id)
      expect(membership.is_primary).to eq(true)
      expect(membership.joined_via_invitation_id).to eq(invitation.id)
    end

    it 'gracefully no-ops when invitation has nil subnet_id (backfill window)' do
      invitation = inviter.invitations.create!(user_type: 'consumer', status: 0, subnet_id: nil)

      new_user = User.create!(
        user_name: 'su_orphan', password: password, invited_code: invitation.invitation_code
      )

      expect(new_user.subnet_memberships).to be_empty
    end
  end
end
