require 'rails_helper'

RSpec.describe InvitationRedemption, type: :model, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:creator) { User.create!(user_name: 'ir_creator', password: password) }
  let(:invitation) { creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true) }
  let(:redeemer) { User.create!(user_name: 'ir_redeemer', password: password) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'belongs to an invitation and a user' do
    redemption = invitation.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
    expect(redemption.invitation).to eq(invitation)
    expect(redemption.user).to eq(redeemer)
  end

  it 'rejects a duplicate (invitation, user) pair' do
    invitation.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
    dup = invitation.invitation_redemptions.build(user_id: redeemer.id, redeemed_at: Time.current)
    expect(dup).not_to be_valid
    expect(dup.errors[:user_id]).to be_present
  end

  it 'allows the same user to redeem two different invitations' do
    other = creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true)
    invitation.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
    expect {
      other.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
    }.to change(InvitationRedemption, :count).by(1)
  end
end
