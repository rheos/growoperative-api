require 'rails_helper'

RSpec.describe Foaf::Publisher, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(user_name: 'alice', password: 'password123',
                 foaf_address: '0x' + 'aa' * 20)
  end
  let(:bob) do
    User.create!(user_name: 'bob', password: 'password123',
                 foaf_address: '0x' + 'bb' * 20)
  end
  let(:trustline) do
    Trustline.create!(
      user_a: alice, user_b: bob,
      credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0
    )
  end
  let(:tx_row) do
    trustline.trustline_transactions.create!(
      amount: 10, description: 'shared write', transaction_type: 'payment',
      initiated_by: alice, balance_after: 10, foaf_direction: 'sent',
      foaf_posted_at: nil
    )
  end
  let(:fake_client) { instance_double(Foaf::Client) }
  let(:idempotency_key) { "growoperative:trustline_transaction:#{tx_row.id}" }

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:networks).and_return([{ 'address' => '0xnetwork' }])
    allow(Foaf::Signer).to receive(:ensure_keypair!)
    allow(Foaf::Signer).to receive(:address_for) { |user| user.foaf_address }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'creates with a stable idempotency key and confirms with the receiver signer' do
    allow(fake_client).to receive(:pending_transfer_by_idempotency_key)
      .with(idempotency_key: idempotency_key)
      .and_return(not_found)
    expect(fake_client).to receive(:create_pending_transfer).with(
      hash_including(
        network_address: '0xnetwork',
        from_address: alice.foaf_address,
        to_address: bob.foaf_address,
        value: 10.0,
        idempotency_key: idempotency_key
      )
    ).and_return(success(pending_payload))
    expect(fake_client).to receive(:confirm_transfer).with(
      pending_transfer_id: 42,
      signer_address: bob.foaf_address
    ).and_return(success(confirmed_payload))

    described_class.new.publish_payment(
      trustline, 10, alice, bob, tx_row: tx_row
    )

    expect(tx_row.reload).to have_attributes(
      foaf_pending_transfer_id: 42,
      foaf_operation_id: 999,
      foaf_write_state: 'posted'
    )
    expect(tx_row.foaf_posted_at).not_to be_nil
    expect(tx_row.foaf_write_error).to be_nil
  end

  it 'maps settlement to the inverse transfer and still uses its receiver signer' do
    allow(fake_client).to receive(:pending_transfer_by_idempotency_key)
      .and_return(not_found)
    expect(fake_client).to receive(:create_pending_transfer).with(
      hash_including(
        from_address: bob.foaf_address,
        to_address: alice.foaf_address,
        idempotency_key: idempotency_key
      )
    ).and_return(success(
      pending_payload.merge('from' => bob.foaf_address, 'to' => alice.foaf_address)
    ))
    expect(fake_client).to receive(:confirm_transfer).with(
      pending_transfer_id: 42,
      signer_address: alice.foaf_address
    ).and_return(success(confirmed_payload))

    described_class.new.publish_settlement(
      trustline, 10, alice, bob, tx_row: tx_row
    )

    expect(tx_row.reload.foaf_operation_id).to eq(999)
  end

  it 'resolves an ambiguous create by deterministic-key lookup without recreating' do
    allow(fake_client).to receive(:pending_transfer_by_idempotency_key)
      .with(idempotency_key: idempotency_key)
      .and_return(
        not_found,
        success(pending_payload.merge('status' => 'confirmed', 'operation' => 777))
      )
    expect(fake_client).to receive(:create_pending_transfer).once.and_return(
      ambiguous(503, '{"error":"unavailable"}')
    )
    expect(fake_client).not_to receive(:confirm_transfer)

    described_class.new.publish_payment(
      trustline, 10, alice, bob, tx_row: tx_row
    )

    expect(tx_row.reload).to have_attributes(
      foaf_operation_id: 777,
      foaf_write_state: 'posted'
    )
  end

  it 'resolves an ambiguous confirm by reading the retained pending transfer' do
    allow(fake_client).to receive(:pending_transfer_by_idempotency_key)
      .and_return(not_found)
    allow(fake_client).to receive(:create_pending_transfer)
      .and_return(success(pending_payload))
    allow(fake_client).to receive(:confirm_transfer)
      .and_return(ambiguous(0, nil))
    expect(fake_client).to receive(:pending_transfer)
      .with(pending_transfer_id: 42)
      .and_return(
        success(pending_payload.merge('status' => 'confirmed', 'operation' => 888))
      )

    described_class.new.publish_payment(
      trustline, 10, alice, bob, tx_row: tx_row
    )

    expect(tx_row.reload).to have_attributes(
      foaf_pending_transfer_id: 42,
      foaf_operation_id: 888,
      foaf_write_state: 'posted'
    )
  end

  it 'reads before an idempotent confirm retry when the first result remains ambiguous' do
    allow(fake_client).to receive(:pending_transfer_by_idempotency_key)
      .and_return(not_found)
    expect(fake_client).to receive(:create_pending_transfer).once
      .and_return(success(pending_payload))
    expect(fake_client).to receive(:confirm_transfer).twice
      .and_return(ambiguous(503, 'gateway timeout'), success(confirmed_payload))
    expect(fake_client).to receive(:pending_transfer).twice
      .with(pending_transfer_id: 42)
      .and_return(success(pending_payload), success(pending_payload))

    publisher = described_class.new
    publisher.publish_payment(trustline, 10, alice, bob, tx_row: tx_row)

    expect(tx_row.reload).to have_attributes(
      foaf_pending_transfer_id: 42,
      foaf_write_state: 'ambiguous_confirm',
      foaf_posted_at: nil
    )

    publisher.publish_payment(trustline, 10, alice, bob, tx_row: tx_row)

    expect(tx_row.reload).to have_attributes(
      foaf_operation_id: 999,
      foaf_write_state: 'posted'
    )
  end

  def pending_payload
    {
      'id' => 42,
      'idempotencyKey' => idempotency_key,
      'networkAddress' => '0xnetwork',
      'from' => alice.foaf_address,
      'to' => bob.foaf_address,
      'value' => 10.0,
      'status' => 'pending',
      'operation' => nil
    }
  end

  def confirmed_payload
    {
      'status' => 'confirmed',
      'operation' => 999,
      'transfer' => pending_payload.merge(
        'status' => 'confirmed',
        'operation' => 999
      )
    }
  end

  def success(data, status = 200)
    {
      'ok' => true,
      'status' => status,
      'outcome' => 'success',
      'body' => data.to_json,
      'data' => data
    }
  end

  def not_found
    {
      'ok' => false,
      'status' => 404,
      'outcome' => 'rejected',
      'body' => '{"error":"not found"}',
      'error' => '{"error":"not found"}'
    }
  end

  def ambiguous(status, body)
    {
      'ok' => false,
      'status' => status,
      'outcome' => 'ambiguous',
      'body' => body,
      'error' => body || 'timeout'
    }
  end
end
