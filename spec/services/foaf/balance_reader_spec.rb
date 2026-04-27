require 'rails_helper'

RSpec.describe Foaf::BalanceReader, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(user_name: 'alice', password: 'password123',
                 foaf_address: '0x' + 'aa' * 20)
  end
  let(:bob) do
    User.create!(user_name: 'bob', password: 'password123',
                 foaf_address: '0x' + 'bb' * 20)
  end
  let(:carol) do
    User.create!(user_name: 'carol', password: 'password123',
                 foaf_address: '0x' + 'cc' * 20)
  end

  let!(:trustline_ab) do
    Trustline.create!(
      user_a: alice, user_b: bob,
      credit_limit_a_to_b: 100, credit_limit_b_to_a: 200, current_balance: 0
    )
  end

  # Resolve canonical sides (trustline enforces user_a_id < user_b_id).
  let(:canonical_user_a) { trustline_ab.user_a }
  let(:canonical_user_b) { trustline_ab.user_b }

  let(:fake_client) { instance_double(Foaf::Client) }

  before do
    allow(Foaf::Config).to receive(:shadow_mode?).and_return(true)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:networks).and_return([{ 'address' => '0xnetwork' }])
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  # FOAF returns balance/limits from the queried user's perspective.
  # `balance` > 0 means counterparty owes queried user.
  def foaf_trustline(counter_party:, balance:, given:, received:)
    {
      'counterParty' => counter_party,
      'balance'      => balance,
      'given'        => given,
      'received'     => received,
    }
  end

  describe '.fetch' do
    it 'returns [] without hitting FOAF when user has no active trustlines' do
      expect(fake_client).not_to receive(:user_trustlines)
      expect(described_class.fetch(carol)).to eq([])
    end

    it 'returns nil when user has trustlines but no foaf_address' do
      canonical_user_a.update!(foaf_address: nil)
      expect(described_class.fetch(canonical_user_a)).to be_nil
    end

    it 'returns nil when FOAF has no networks' do
      allow(fake_client).to receive(:networks).and_return([])
      expect(described_class.fetch(canonical_user_a)).to be_nil
    end

    it 'returns nil when the FOAF API call fails' do
      allow(fake_client).to receive(:user_trustlines).and_return(nil)
      expect(described_class.fetch(canonical_user_a)).to be_nil
    end

    it 'maps FOAF balance into viewer-perspective for user_a' do
      # From canonical_user_a's query: balance = -80 means A owes B $80 (app)
      allow(fake_client).to receive(:user_trustlines).with(
        network_address: '0xnetwork',
        user_address: canonical_user_a.foaf_address,
      ).and_return([
        foaf_trustline(counter_party: canonical_user_b.foaf_address,
                       balance: -80.0, given: 200.0, received: 100.0),
      ])

      rows = described_class.fetch(canonical_user_a)
      expect(rows.size).to eq(1)
      row = rows.first
      expect(row[:trustline].id).to eq(trustline_ab.id)
      expect(row[:counterparty].id).to eq(canonical_user_b.id)
      expect(row[:viewer_balance]).to eq(80.0)       # A owes B
      expect(row[:my_credit_limit]).to eq(100.0)     # A can borrow up to 100
      expect(row[:their_credit_limit]).to eq(200.0)  # B can borrow up to 200
    end

    it 'maps FOAF balance into viewer-perspective for user_b (same formula)' do
      # From canonical_user_b's query: balance = +80 (A owes me B $80).
      # Viewer-balance for B: negative = counterparty owes me.
      allow(fake_client).to receive(:user_trustlines).with(
        network_address: '0xnetwork',
        user_address: canonical_user_b.foaf_address,
      ).and_return([
        foaf_trustline(counter_party: canonical_user_a.foaf_address,
                       balance: 80.0, given: 100.0, received: 200.0),
      ])

      rows = described_class.fetch(canonical_user_b)
      expect(rows.size).to eq(1)
      row = rows.first
      expect(row[:counterparty].id).to eq(canonical_user_a.id)
      expect(row[:viewer_balance]).to eq(-80.0)      # A owes B, so from B's POV it's negative
      expect(row[:my_credit_limit]).to eq(200.0)     # B can borrow up to 200
      expect(row[:their_credit_limit]).to eq(100.0)  # A can borrow up to 100
    end

    it 'skips FOAF rows without a matching active Rails trustline' do
      allow(fake_client).to receive(:user_trustlines).and_return([
        foaf_trustline(counter_party: canonical_user_b.foaf_address,
                       balance: 0, given: 200, received: 100),
        foaf_trustline(counter_party: '0x' + 'ff' * 20,  # stranger
                       balance: 50, given: 500, received: 500),
      ])
      rows = described_class.fetch(canonical_user_a)
      expect(rows.size).to eq(1)
      expect(rows.first[:counterparty].id).to eq(canonical_user_b.id)
    end

    it 'skips trustlines whose counterparty has no foaf_address' do
      canonical_user_b.update!(foaf_address: nil)
      allow(fake_client).to receive(:user_trustlines).and_return([])
      rows = described_class.fetch(canonical_user_a)
      expect(rows).to eq([])
    end
  end
end
