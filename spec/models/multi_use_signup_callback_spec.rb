require 'rails_helper'

# Exercises User#update_invitiation_limit (after_create) for multi-use codes.
# Creating a User with `invited_code` fires the signup callback chain — the
# same path real signup runs through after the auth.foaf.io round-trip.
RSpec.describe 'Multi-use invitation signup callback', type: :model, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:creator) { User.create!(user_name: 'muc_creator', password: password, invite_limit: 5) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def make_multi_use(code:)
    creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: code)
  end

  def relationship_between(a, b)
    Relationship.where(
      '(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)',
      a.id, b.id, b.id, a.id,
    )
  end

  it 'records a redemption instead of flipping status/accepted_id' do
    invitation = make_multi_use(code: 'MULTI001')
    redeemer = User.create!(user_name: 'muc_redeemer1', password: password, invited_code: invitation.invitation_code)

    invitation.reload
    expect(invitation.status).to eq('pending')
    expect(invitation.accepted_id).to be_nil
    expect(invitation.invitation_redemptions.where(user_id: redeemer.id).count).to eq(1)
  end

  it 'still creates the role group and the creator->redeemer relationship' do
    invitation = make_multi_use(code: 'MULTI002')
    redeemer = User.create!(user_name: 'muc_redeemer2', password: password, invited_code: invitation.invitation_code)

    expect(redeemer.user_groups.where(group_label: 'consumer').count).to eq(1)
    expect(relationship_between(creator, redeemer).count).to eq(1)
  end

  it 'a second signup creates a second redemption, code stays pending, creator is first contact of both' do
    invitation = make_multi_use(code: 'MULTI003')
    r1 = User.create!(user_name: 'muc_first', password: password, invited_code: invitation.invitation_code)
    r2 = User.create!(user_name: 'muc_second', password: password, invited_code: invitation.invitation_code)

    invitation.reload
    expect(invitation.status).to eq('pending')
    expect(invitation.accepted_id).to be_nil
    expect(invitation.invitation_redemptions.count).to eq(2)
    expect(invitation.redeemers).to contain_exactly(r1, r2)

    # set_parent makes the creator the parent (first contact) of each redeemer.
    expect(r1.parent_id).to eq(creator.id)
    expect(r2.parent_id).to eq(creator.id)
    expect(relationship_between(creator, r1).count).to eq(1)
    expect(relationship_between(creator, r2).count).to eq(1)
  end

  it 'bumps the creator invitations_count on each redemption' do
    invitation = make_multi_use(code: 'MULTI004')
    expect {
      User.create!(user_name: 'muc_count1', password: password, invited_code: invitation.invitation_code)
      User.create!(user_name: 'muc_count2', password: password, invited_code: invitation.invitation_code)
    }.to change { creator.reload.invitations_count }.by(2)
  end

  it 'leaves single-use behaviour unchanged (flips to accepted)' do
    invitation = creator.invitations.create!(user_type: 'consumer', status: 0, invitation_code: 'SINGLE01')
    redeemer = User.create!(user_name: 'muc_single', password: password, invited_code: invitation.invitation_code)

    invitation.reload
    expect(invitation.status).to eq('accepted')
    expect(invitation.accepted_id).to eq(redeemer.id)
    expect(invitation.invitation_redemptions.count).to eq(0)
  end

  it 'keeps invited_by_name tied to the redeemed multi-use invitation after code reuse' do
    old_inviter = creator
    old_invitation = make_multi_use(code: 'REUSEME')
    redeemer = User.create!(user_name: 'muc_reuse_redeemer', password: password, invited_code: old_invitation.invitation_code)
    old_invitation.update!(disabled_at: Time.current)

    new_inviter = User.create!(user_name: 'muc_new_inviter', password: password)
    new_inviter.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, invitation_code: 'REUSEME')

    expect(redeemer.invited_by_name).to eq(old_inviter.user_name)
  end
end
