require 'rails_helper'

RSpec.describe Invitation, type: :model, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:creator) { User.create!(user_name: 'inv_creator', password: password) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'multi-use flags' do
    it 'defaults to single-use (multi_use false) and active (disabled_at nil)' do
      inv = creator.invitations.create!(user_type: 'consumer', status: 0)
      expect(inv.multi_use?).to eq(false)
      expect(inv.active?).to eq(true)
      expect(inv.disabled_at).to be_nil
    end

    it 'reports multi_use? when the flag is set' do
      inv = creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true)
      expect(inv.multi_use?).to eq(true)
    end

    it 'reports active? false once disabled_at is set' do
      inv = creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, disabled_at: Time.current)
      expect(inv.active?).to eq(false)
    end
  end

  describe 'redemption associations' do
    let(:invitation) { creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true) }
    let(:redeemer) { User.create!(user_name: 'inv_redeemer', password: password) }

    it 'has many redemptions and redeemers through them' do
      invitation.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
      expect(invitation.invitation_redemptions.count).to eq(1)
      expect(invitation.redeemers).to include(redeemer)
    end

    it 'destroys redemptions when the invitation is destroyed' do
      invitation.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
      expect { invitation.destroy }.to change(InvitationRedemption, :count).by(-1)
    end
  end
end
