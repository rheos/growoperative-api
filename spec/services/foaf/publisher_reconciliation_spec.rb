require 'rails_helper'

RSpec.describe Foaf::Publisher, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(
      user_name: 'alice',
      password: 'password123',
      foaf_address: '0x' + 'aa' * 20
    )
  end
  let(:bob) do
    User.create!(
      user_name: 'bob',
      password: 'password123',
      foaf_address: '0x' + 'bb' * 20
    )
  end
  let(:trustline) do
    Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 40,
      current_balance: 25
    )
  end
  let(:fake_client) { instance_double(Foaf::Client) }

  before do
    # Preserve the canonical user_a/user_b order regardless of lazy let access
    # in an individual example.
    alice
    bob
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:networks).and_return([{ 'address' => '0xnetwork' }])
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'maps raw FOAF balance and limits into the app user_a perspective' do
    allow(fake_client).to receive(:user_trustlines).and_return([{
      'counterParty' => bob.foaf_address,
      'balance' => -25,
      'given' => 40,
      'received' => 100
    }])

    expect(described_class.new.reconcile_trustline(trustline)).to be_nil
  end

  it 'reports discrepancies using the correctly mapped values' do
    allow(fake_client).to receive(:user_trustlines).and_return([{
      'counterParty' => bob.foaf_address,
      'balance' => 25,
      'given' => 100,
      'received' => 40
    }])

    expect(described_class.new.reconcile_trustline(trustline)).to eq(
      balance: {
        local: 25.0,
        foaf: -25.0,
        notional_balance: 25.0,
        foaf_balance: -25.0,
        credloop_delta: 50.0
      },
      given: { local: 40.0, foaf: 100.0 },
      received: { local: 100.0, foaf: 40.0 }
    )
  end
end
