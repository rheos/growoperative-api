require 'rails_helper'

RSpec.describe SubnetMembership, type: :model do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'prevents duplicate memberships in the same subnet' do
    user = User.create!(user_name: "sm_user_#{SecureRandom.hex(4)}", password: 'bobsentme!')
    subnet = create(:subnet)
    create(:subnet_membership, user: user, subnet: subnet)

    dup = build(:subnet_membership, user: user, subnet: subnet)
    expect(dup).not_to be_valid
  end

  it 'allows a user to belong to multiple different subnets' do
    user = User.create!(user_name: "sm_user_#{SecureRandom.hex(4)}", password: 'bobsentme!')
    create(:subnet_membership, user: user, subnet: create(:subnet), is_primary: true)
    other = build(:subnet_membership, user: user, subnet: create(:subnet), is_primary: false)
    expect(other).to be_valid
  end

  it 'blocks a second primary membership for the same user' do
    user = User.create!(user_name: "sm_user_#{SecureRandom.hex(4)}", password: 'bobsentme!')
    create(:subnet_membership, user: user, subnet: create(:subnet), is_primary: true)

    second_primary = build(:subnet_membership, user: user, subnet: create(:subnet), is_primary: true)
    expect(second_primary).not_to be_valid
    expect(second_primary.errors[:is_primary]).to be_present
  end
end
