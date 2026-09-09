require 'rails_helper'

RSpec.describe 'Open registration', type: :request, skip_hooks: true do
  let(:password) { 'OpenSignup1!' }

  before { DatabaseCleaner.clean_with(:truncation) }
  after { DatabaseCleaner.clean_with(:truncation) }

  def signup(user_name:, code: :omitted, code_key: :invite_code)
    user_params = {
      user_name: user_name,
      first_name: 'Open',
      password: password,
      password_confirmation: password,
    }
    user_params[code_key] = code unless code == :omitted
    post '/v1/signup', params: { user: user_params }
  end

  def parsed
    JSON.parse(response.body)
  end

  it 'creates an unconnected broker root when the invite code is omitted' do
    signup(user_name: 'open_root')

    expect(response).to have_http_status(:created)
    root = User.find_by!(user_name: 'open_root')
    expect(root.depth).to eq(0)
    expect(root.invited_code).to be_nil
    expect(root.parent_id).to be_nil
    expect(root.user_groups.pluck(:group_label)).to eq(['broker'])
    expect(root.subnet_memberships).to be_empty
    expect(Relationship.where('user_id = ? OR friend_id = ?', root.id, root.id)).to be_empty
    expect(AuthFoafClient).to have_received(:signup).with(
      hash_including(user_name: 'open_root', invited_by_foaf_id: nil),
    )
  end

  it 'normalizes a blank invite code and creates the same unconnected account' do
    signup(user_name: 'blank_code_root', code: '', code_key: :invited_code)

    expect(response).to have_http_status(:created)
    root = User.find_by!(user_name: 'blank_code_root')
    expect(root.invited_code).to be_nil
    expect(root.user_groups.pluck(:group_label)).to eq(['broker'])
    expect(Relationship.where('user_id = ? OR friend_id = ?', root.id, root.id)).to be_empty
  end

  it 'still rejects a supplied invalid invite before creating either profile' do
    signup(user_name: 'invalid_code_user', code: 'NOTREAL')

    expect(response).to have_http_status(:unprocessable_content)
    expect(parsed['message']).to eq('Invitation code is wrong')
    expect(User.find_by(user_name: 'invalid_code_user')).to be_nil
    expect(AuthFoafClient).not_to have_received(:signup)
  end

  it 'lets an open-registration root invite another member through the existing flow' do
    GlobalSetting.create!(setting: 'ChainLimit', value: 3)
    signup(user_name: 'inviting_root')
    expect(response).to have_http_status(:created)
    root = User.find_by!(user_name: 'inviting_root')

    invitation = root.invitations.create!(
      user_type: 'consumer',
      status: :pending,
      invitation_code: 'ROOT1234',
    )
    signup(user_name: 'invited_member', code: invitation.invitation_code)

    expect(response).to have_http_status(:created)
    member = User.find_by!(user_name: 'invited_member')
    expect(member.parent_id).to eq(root.id)
    expect(member.depth).to eq(1)
    expect(member.user_groups.pluck(:group_label)).to eq(['consumer'])
    expect(Relationship.where(user_id: root.id, friend_id: member.id)).to exist
    expect(invitation.reload).to be_accepted
    expect(AuthFoafClient).to have_received(:signup).with(
      hash_including(user_name: 'invited_member', invited_by_foaf_id: root.foaf_id),
    )
  end
end
