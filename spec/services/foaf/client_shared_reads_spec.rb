require 'rails_helper'

RSpec.describe Foaf::Client, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  let(:shared_client) { instance_double(Foaf::LedgerClient) }
  let(:client) do
    allow(Foaf::LedgerClient).to receive(:new).and_return(shared_client)
    described_class.new(base_url: 'https://foaf.test')
  end

  it 'parallel-runs a read and returns the package result when enabled' do
    allow(Foaf::Config).to receive(:shared_reads?).and_return(true)
    allow(client).to receive(:get).with('/api/v1/networks').and_return([{ 'source' => 'legacy' }])
    allow(shared_client).to receive(:networks).and_return([{ 'source' => 'shared' }])
    allow(Rails.logger).to receive(:warn)

    expect(client.networks).to eq([{ 'source' => 'shared' }])
    expect(Rails.logger).to have_received(:warn).with(/foaf-client shared-read diff/)
  end

  it 'parallel-runs a read but keeps the legacy result when disabled' do
    allow(Foaf::Config).to receive(:shared_reads?).and_return(false)
    allow(client).to receive(:get).with('/api/v1/networks').and_return([{ 'source' => 'legacy' }])
    allow(shared_client).to receive(:networks).and_return([{ 'source' => 'shared' }])
    allow(Rails.logger).to receive(:warn)

    expect(client.networks).to eq([{ 'source' => 'legacy' }])
  end

  it 'parallel-runs max-capacity path reads with the upstream address workaround' do
    allow(Foaf::Config).to receive(:shared_reads?).and_return(true)
    body = {
      address: "network",
      from: "sender",
      to: "receiver"
    }
    allow(client).to receive(:post)
      .with("/api/v1/networks/network/max-capacity-path-info", body)
      .and_return("capacity" => "10", "path" => %w[sender receiver])
    expect(shared_client).to receive(:max_capacity_path_info).with(
      network_address: "network",
      from_address: "sender",
      to_address: "receiver"
    ).and_return("capacity" => "10", "path" => %w[sender receiver])

    expect(
      client.max_capacity_path_info(
        network_address: "network",
        from_address: "sender",
        to_address: "receiver"
      )
    ).to eq("capacity" => "10", "path" => %w[sender receiver])
  end

  it 'keeps mutating trustline calls on the legacy implementation when shared writes are disabled' do
    allow(Foaf::Config).to receive(:shared_writes?).and_return(false)
    expect(shared_client).not_to receive(:update_trustline)
    expect(client).to receive(:post).with(
      '/api/v1/networks/network/trustlines/update',
      {
        creditor_address: 'creditor',
        debtor_address: 'debtor',
        creditline_given: '10',
        creditline_received: '20'
      }
    ).and_return('legacy-write')

    expect(
      client.update_trustline(
        network_address: 'network',
        creditor_address: 'creditor',
        debtor_address: 'debtor',
        creditline_given: '10',
        creditline_received: '20'
      )
    ).to eq('legacy-write')
  end

  it 'routes trustline updates through the shared client and preserves the strict result' do
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    expect(client).not_to receive(:post)
    expect(shared_client).to receive(:update_trustline).with(
      network_address: 'network',
      creditor_address: 'creditor',
      debtor_address: 'debtor',
      creditline_given: '10',
      creditline_received: '20'
    ).and_return(
      'ok' => true,
      'status' => 201,
      'body' => '{"action":"accepted"}',
      'data' => { 'action' => 'accepted' }
    )

    result = client.update_trustline(
      network_address: 'network',
      creditor_address: 'creditor',
      debtor_address: 'debtor',
      creditline_given: '10',
      creditline_received: '20'
    )

    expect(result).to include(
      'ok' => true,
      'status' => 201,
      'outcome' => 'success',
      'body' => '{"action":"accepted"}',
      'data' => { 'action' => 'accepted' }
    )
  end

  it 'routes all pending-transfer mutations through the shared client' do
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    expect(client).not_to receive(:post)
    expect(client).not_to receive(:put)

    expect(shared_client).to receive(:create_pending_transfer).with(
      network_address: 'network',
      from_address: 'sender',
      to_address: 'receiver',
      value: '3.25',
      extra_data: '{"order_id":7}',
      idempotency_key: 'growoperative:trustline_transaction:7'
    ).and_return(
      'ok' => true, 'status' => 201, 'body' => '{"id":41}',
      'data' => { 'id' => 41 }
    )
    expect(shared_client).to receive(:confirm_transfer).with(
      pending_transfer_id: 41,
      signer_address: 'receiver'
    ).and_return(
      'ok' => true, 'status' => 200, 'body' => '{"operation":91}',
      'data' => { 'operation' => 91 }
    )
    expect(shared_client).to receive(:reject_transfer).with(
      pending_transfer_id: 42,
      signer_address: 'receiver',
      reason: 'declined'
    ).and_return(
      'ok' => true, 'status' => 200, 'body' => '{"status":"rejected"}',
      'data' => { 'status' => 'rejected' }
    )

    pending = client.create_pending_transfer(
      network_address: 'network',
      from_address: 'sender',
      to_address: 'receiver',
      value: '3.25',
      extra_data: '{"order_id":7}',
      idempotency_key: 'growoperative:trustline_transaction:7'
    )
    confirmed = client.confirm_transfer(
      pending_transfer_id: 41,
      signer_address: 'receiver'
    )
    rejected = client.reject_transfer(
      pending_transfer_id: 42,
      signer_address: 'receiver',
      reason: 'declined'
    )

    expect(pending).to include(
      'outcome' => 'success',
      'status' => 201,
      'data' => { 'id' => 41 }
    )
    expect(confirmed).to include(
      'outcome' => 'success',
      'status' => 200,
      'data' => { 'operation' => 91 }
    )
    expect(rejected).to include(
      'outcome' => 'success',
      'status' => 200,
      'data' => { 'status' => 'rejected' }
    )
  end

  it 'keeps all pending-transfer mutations on the legacy transport when shared writes are disabled' do
    allow(Foaf::Config).to receive(:shared_writes?).and_return(false)
    expect(shared_client).not_to receive(:create_pending_transfer)
    expect(shared_client).not_to receive(:confirm_transfer)
    expect(shared_client).not_to receive(:reject_transfer)

    expect(client).to receive(:post).with(
      '/api/v1/pending_transfers',
      {
        network_address: 'network',
        from_address: 'sender',
        to_address: 'receiver',
        value: '3.25',
        extra_data: nil
      }
    ).and_return('legacy-pending')
    expect(client).to receive(:put).with(
      '/api/v1/pending_transfers/41/confirm'
    ).and_return('legacy-confirmed')
    expect(client).to receive(:put).with(
      '/api/v1/pending_transfers/42/reject',
      { reason: 'declined' }
    ).and_return('legacy-rejected')

    expect(
      client.create_pending_transfer(
        network_address: 'network',
        from_address: 'sender',
        to_address: 'receiver',
        value: '3.25'
      )
    ).to eq('legacy-pending')
    expect(
      client.confirm_transfer(
        pending_transfer_id: 41,
        signer_address: 'receiver'
      )
    ).to eq('legacy-confirmed')
    expect(
      client.reject_transfer(
        pending_transfer_id: 42,
        signer_address: 'receiver',
        reason: 'declined'
      )
    ).to eq('legacy-rejected')
  end

  it 'does not retry a failed shared mutation through the legacy transport' do
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    allow(Rails.logger).to receive(:warn)
    expect(client).not_to receive(:post)
    expect(shared_client).to receive(:create_pending_transfer).and_return(
      'ok' => false,
      'status' => 503,
      'body' => '{"error":"temporarily unavailable"}',
      'error' => '{"error":"temporarily unavailable"}'
    )

    result = client.create_pending_transfer(
      network_address: 'network',
      from_address: 'sender',
      to_address: 'receiver',
      value: '3.25'
    )

    expect(result).to include(
      'ok' => false,
      'status' => 503,
      'outcome' => 'ambiguous',
      'body' => '{"error":"temporarily unavailable"}'
    )
    expect(Rails.logger).to have_received(:warn).with(
      /method=create_pending_transfer outcome=ambiguous status=503/
    )
  end

  it 'distinguishes a definitive shared-write rejection from ambiguity' do
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    allow(Rails.logger).to receive(:warn)
    expect(shared_client).to receive(:confirm_transfer).and_return(
      'ok' => false,
      'status' => 422,
      'body' => '{"error":"InsufficientCapacity"}',
      'error' => '{"error":"InsufficientCapacity"}'
    )

    result = client.confirm_transfer(
      pending_transfer_id: 41,
      signer_address: 'receiver'
    )

    expect(result).to include(
      'ok' => false,
      'status' => 422,
      'outcome' => 'rejected',
      'body' => '{"error":"InsufficientCapacity"}'
    )
  end

  it 'bridges an address to the app-owned signer for exact-body signatures' do
    private_key = '1' * 64
    address = Foaf::LedgerSigner.address(private_key)
    user = User.create!(
      user_name: 'shared-write-signer',
      password: 'password123',
      foaf_address: address,
      foaf_private_key: private_key
    )
    payload = '{"value":"3.25"}'

    expect(Foaf::Signer).to receive(:sign).with(user, payload).and_return('0xsigned')

    expect(client.send(:sign_shared_payload, address.upcase, payload)).to eq('0xsigned')
  end
end
