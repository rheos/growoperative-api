require 'rails_helper'

# Job 14 acceptance: demo snapshot/reset must not leave previously-issued
# tokens authenticating against reset identities. Phase 3 (Job 29) wires
# the auth.foaf.io revocation snapshot for this; in Phase 2 we rotate
# `foaf_id` on every core demo user so pre-reset tokens stop resolving.
RSpec.describe DemoResetService do
  let!(:alice) do
    u = User.create!(
      user_name: 'reset_alice',
      email: 'reset_alice@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
    u.user_groups.create!(group_label: 'demo')
    u
  end

  let!(:bob) do
    u = User.create!(
      user_name: 'reset_bob',
      email: 'reset_bob@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
    u.user_groups.create!(group_label: 'demo')
    u
  end

  let(:minimal_snapshot) do
    {
      'captured_at' => Time.current.iso8601,
      'core_usernames' => %w[reset_alice reset_bob],
      'users' => [
        { 'user_name' => 'reset_alice', 'name' => nil, 'nickname' => nil,
          'depth' => 0, 'invite_limit' => 0, 'invitation_limit' => 0,
          'invitations_count' => 0, 'parent_user_name' => nil },
        { 'user_name' => 'reset_bob', 'name' => nil, 'nickname' => nil,
          'depth' => 0, 'invite_limit' => 0, 'invitation_limit' => 0,
          'invitations_count' => 0, 'parent_user_name' => nil },
      ],
      'user_groups' => [
        { 'user_name' => 'reset_alice', 'group_label' => 'demo' },
        { 'user_name' => 'reset_bob', 'group_label' => 'demo' },
      ],
    }
  end

  before do
    allow(DemoSnapshotService).to receive(:load).with('default').and_return(minimal_snapshot)
  end

  it 'rotates foaf_id for every core demo user' do
    alice_before = alice.foaf_id
    bob_before = bob.foaf_id

    DemoResetService.new.call

    expect(alice.reload.foaf_id).to be_present
    expect(bob.reload.foaf_id).to be_present
    expect(alice.foaf_id).not_to eq(alice_before)
    expect(bob.foaf_id).not_to eq(bob_before)
  end

  it 'invalidates tokens issued before reset' do
    pre_reset_token = JwtGenerationService.new(alice).token

    DemoResetService.new.call

    decoded = JwtDecodingService.new(pre_reset_token).decrypt!
    expect(decoded['sub']).to be_present
    # The pre-reset sub no longer resolves to any user — api_controller's
    # resolve_user_from_jwt returns nil and the request is rejected.
    expect(User.find_by(foaf_id: decoded['sub'])).to be_nil
  end

  it 'preserves the user_name (so snapshot restore still locates the row)' do
    DemoResetService.new.call
    expect(User.exists?(user_name: 'reset_alice')).to be true
    expect(User.exists?(user_name: 'reset_bob')).to be true
  end
end
