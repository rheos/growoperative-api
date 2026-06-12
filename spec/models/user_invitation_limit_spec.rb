require 'rails_helper'

RSpec.describe User, 'invitation limit counts only pending invitations', type: :model do
  let(:password) { 'bobsentme!' }
  let(:user) { User.create!(user_name: 'uil_inviter', password: password, invite_limit: 3) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'counts pending invitations against the limit' do
    3.times { |n| user.invitations.create!(user_type: 'broker', status: 0, invitation_code: "CODE#{n}".ljust(8, 'X')) }
    expect(user.ramaining_invitation_limit).to eq(0)
  end

  it 'does NOT count accepted invitations — accepted slots free up' do
    3.times { |n| user.invitations.create!(user_type: 'broker', status: 1, invitation_code: "CODE#{n}".ljust(8, 'X')) }
    expect(user.ramaining_invitation_limit).to eq(3)
  end

  it 'only pending + unaccepted consume limit' do
    user.invitations.create!(user_type: 'broker', status: 0, invitation_code: 'PENDING1')
    user.invitations.create!(user_type: 'broker', status: 0, invitation_code: 'PENDING2')
    user.invitations.create!(user_type: 'broker', status: 1, invitation_code: 'USED0001')
    user.invitations.create!(user_type: 'broker', status: 1, invitation_code: 'USED0002')
    expect(user.ramaining_invitation_limit).to eq(1) # 3 limit - 2 pending
  end

  it 'does not count pending multi-use invitations against the normal slot limit' do
    user.invitations.create!(user_type: 'broker', status: 0, invitation_code: 'PENDING1')
    user.invitations.create!(user_type: 'broker', status: 0, multi_use: true, invitation_code: 'MULTIP1')
    user.invitations.create!(user_type: 'broker', status: 0, multi_use: true, invitation_code: 'MULTIP2')

    expect(user.ramaining_invitation_limit).to eq(2)
  end
end
