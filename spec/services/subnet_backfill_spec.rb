require 'rails_helper'

RSpec.describe SubnetBackfill do
  before(:each) { DatabaseCleaner.clean_with(:truncation) }
  after(:each)  { DatabaseCleaner.clean_with(:truncation) }

  let(:password) { 'bobsentme!' }

  def create_user(name, parent: nil)
    User.create!(user_name: name, password: password, parent_id: parent&.id)
  end

  it 'creates a single subnet seeded at the first user' do
    bob = create_user('sb_bob')
    SubnetBackfill.run!

    expect(Subnet.count).to eq(1)
    expect(Subnet.first.seed_user_id).to eq(bob.id)
    expect(Subnet.first.name).to match(/sb_bob/i)
  end

  it 'seeds a minimal config when no override is given (falls through to SiteConfig defaults)' do
    create_user('sb_bob')
    SubnetBackfill.run!

    subnet = Subnet.first
    stored = subnet.current_config.config
    effective = SiteConfig.for(subnet)

    expect(stored.keys).to contain_exactly('chain_limit')
    expect(effective[:multi_role]).to eq(SiteConfig::DEFAULTS[:multi_role])
    expect(effective[:demo_mode]).to eq(SiteConfig::DEFAULTS[:demo_mode])
  end

  it 'accepts an explicit config override (e.g. launch config)' do
    create_user('sb_bob')
    SubnetBackfill.run!(
      subnet_name: 'Crawford Bay',
      config: { multi_role: false, visible_roles: ['broker'], demo_mode: false }
    )

    subnet = Subnet.first
    expect(subnet.name).to eq('Crawford Bay')
    stored = subnet.current_config.config
    expect(stored['multi_role']).to eq(false)
    expect(stored['visible_roles']).to eq(['broker'])
  end

  it 'uses the provided subnet_name instead of auto-generating one' do
    create_user('sb_bob')
    SubnetBackfill.run!(subnet_name: 'Somewhere Specific')
    expect(Subnet.first.name).to eq('Somewhere Specific')
  end

  it 'enrolls the seed user and everyone in their invite chain' do
    bob = create_user('sb_bob')
    alice = create_user('sb_alice', parent: bob)
    carol = create_user('sb_carol', parent: alice)

    SubnetBackfill.run!
    subnet = Subnet.first

    expect(subnet.users).to include(bob, alice, carol)
  end

  it 'leaves users outside the invite chain unaffiliated' do
    bob = create_user('sb_bob')
    outsider = create_user('sb_outsider')  # no parent

    SubnetBackfill.run!

    expect(bob.reload.subnet_memberships).not_to be_empty
    expect(outsider.reload.subnet_memberships).to be_empty
  end

  it 'backfills invitations.subnet_id from the inviter primary' do
    bob = create_user('sb_bob')
    inv = bob.invitations.create!(user_type: 'consumer', status: 0, subnet_id: nil)

    SubnetBackfill.run!

    expect(inv.reload.subnet_id).to eq(bob.primary_subnet.id)
  end

  it 'is idempotent — running twice produces the same state' do
    bob = create_user('sb_bob')
    create_user('sb_alice', parent: bob)

    SubnetBackfill.run!
    first = [Subnet.count, SubnetMembership.count, SubnetConfig.count]

    SubnetBackfill.run!
    second = [Subnet.count, SubnetMembership.count, SubnetConfig.count]

    expect(first).to eq(second)
  end

  it 'raises when there are no users to seed from' do
    expect { SubnetBackfill.run! }.to raise_error(/No users exist/)
  end
end
