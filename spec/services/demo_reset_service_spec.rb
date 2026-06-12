require 'rails_helper'

# foaf_id rotation (old Job 14 token-invalidation step) was removed once
# auth.foaf.io became authoritative for demo login: it validates the requested
# foaf_id against a static allowlist, so rotating to random UUIDs broke every
# demo login. Core demo foaf_ids must now stay pinned. These specs assert the
# current behavior (preservation, not rotation) and the audit logging added
# after a 2026-05-22 reset wiped demo data with no record of who ran it.
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

  it 'preserves foaf_id for every core demo user (rotation was removed)' do
    alice_before = alice.foaf_id
    bob_before = bob.foaf_id

    DemoResetService.new.call

    expect(alice.reload.foaf_id).to eq(alice_before)
    expect(bob.reload.foaf_id).to eq(bob_before)
  end

  it 'keeps pre-reset tokens resolvable (foaf_id is pinned)' do
    pre_reset_token = JwtGenerationService.new(alice).token

    DemoResetService.new.call

    decoded = JwtDecodingService.new(pre_reset_token).decrypt!
    expect(User.find_by(foaf_id: decoded['sub'])).to eq(alice.reload)
  end

  it 'preserves the user_name (so snapshot restore still locates the row)' do
    DemoResetService.new.call
    expect(User.exists?(user_name: 'reset_alice')).to be true
    expect(User.exists?(user_name: 'reset_bob')).to be true
  end

  describe 'notification wipe' do
    let!(:outsider) do
      User.create!(
        user_name: 'reset_outsider',
        email: 'reset_outsider@example.com',
        password: 'bobsentme!',
        password_confirmation: 'bobsentme!',
      )
    end

    def make_notification(recipient:, actor:)
      Notification.create!(
        recipient: recipient, actor: actor,
        notification_type: 'request_created', message: 'reset wipe test'
      )
    end

    it 'deletes notifications where an affected user is the recipient OR the actor' do
      as_recipient = make_notification(recipient: alice, actor: outsider)
      as_actor     = make_notification(recipient: outsider, actor: alice)
      unrelated    = make_notification(recipient: outsider, actor: outsider)

      DemoResetService.new.call

      expect(Notification.exists?(as_recipient.id)).to be false
      expect(Notification.exists?(as_actor.id)).to be false
      expect(Notification.exists?(unrelated.id)).to be true
    end
  end

  describe 'audit logging' do
    it 'records a started and a succeeded entry with the actor and source' do
      DemoResetService.new(source: 'api', actor_user: bob).call

      entries = AuditLog.where(action: 'demo.reset').order(:created_at)
      expect(entries.map(&:status)).to eq(%w[started succeeded])
      expect(entries.map(&:source).uniq).to eq(['api'])
      expect(entries.map(&:actor).uniq).to eq([bob.user_name])
      expect(entries.map(&:actor_user_id).uniq).to eq([bob.id])
      expect(entries.last.metadata['snapshot_name']).to eq('default')
      expect(entries.last.metadata['duration_ms']).to be_a(Integer)
    end

    it 'records a failed entry (and re-raises) when the reset blows up' do
      allow_any_instance_of(DemoResetService)
        .to receive(:restore_core_demo_data).and_raise(StandardError, 'boom')

      expect { DemoResetService.new(source: 'rake', actor: 'system:rake').call }
        .to raise_error(StandardError, 'boom')

      entries = AuditLog.where(action: 'demo.reset').order(:created_at)
      expect(entries.map(&:status)).to eq(%w[started failed])
      # The 'started' entry survives the rolled-back transaction.
      expect(entries.first.status).to eq('started')
      expect(entries.last.metadata['error']).to eq('boom')
      expect(entries.last.actor).to eq('system:rake')
    end
  end
end
