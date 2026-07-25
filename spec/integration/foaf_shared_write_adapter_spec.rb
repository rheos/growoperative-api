require 'rails_helper'
require 'securerandom'

RSpec.describe 'GrowOperative shared FOAF write adapter', :integration, skip_hooks: true do
  before do
    skip 'set INTEGRATION=1 to run against a live FOAF service' unless ENV['INTEGRATION'] == '1'
    unless ENV['FOAF_SIGNATURE_ENFORCEMENT'] == 'true'
      skip 'set FOAF signature_enforcement=true and FOAF_SIGNATURE_ENFORCEMENT=true'
    end

    @original_shared_writes = ENV['FOAF_SHARED_WRITES']
    ENV['FOAF_SHARED_WRITES'] = 'true'
  end

  after do
    ENV['FOAF_SHARED_WRITES'] = @original_shared_writes
    DatabaseCleaner.clean_with(:truncation)
  end

  it 'creates, signs, and confirms through the app adapter' do
    base_url = ENV.fetch('FOAF_API_URL', 'http://host.docker.internal:3002')
    network_address = ENV.fetch('FOAF_NETWORK_ADDRESS')
    seed_client = Foaf::LedgerClient.new(base_url: base_url)
    sender_keypair = seed_client.generate_keypair
    receiver_keypair = seed_client.generate_keypair

    sender = create_signer_user('sender', sender_keypair)
    receiver = create_signer_user('receiver', receiver_keypair)
    client = Foaf::Client.new(base_url: base_url)

    first_update = client.update_trustline(
      network_address: network_address,
      creditor_address: receiver.foaf_address,
      debtor_address: sender.foaf_address,
      creditline_given: '25',
      creditline_received: '0'
    )
    second_update = client.update_trustline(
      network_address: network_address,
      creditor_address: sender.foaf_address,
      debtor_address: receiver.foaf_address,
      creditline_given: '0',
      creditline_received: '25'
    )
    pending = client.create_pending_transfer(
      network_address: network_address,
      from_address: sender.foaf_address,
      to_address: receiver.foaf_address,
      value: '2.5',
      extra_data: { contract: 'growoperative-shared-write-adapter' }.to_json,
      idempotency_key: "growoperative:signature-contract:#{SecureRandom.hex(12)}"
    )
    expect(pending).to include('outcome' => 'success')
    expect(pending.dig('data', 'id')).not_to be_nil

    confirmed = client.confirm_transfer(
      pending_transfer_id: pending.dig('data', 'id'),
      signer_address: receiver.foaf_address
    )

    expect(first_update).to include('outcome' => 'success')
    expect(first_update.fetch('data')).to include('action')
    expect(second_update).to include('outcome' => 'success')
    expect(second_update.fetch('data')).to include('action')
    expect(confirmed).to include('outcome' => 'success')
    expect(confirmed.fetch('data')).to include('status' => 'confirmed')
    expect(confirmed.dig('data', 'operation')).not_to be_nil
  end

  def create_signer_user(label, keypair)
    User.create!(
      user_name: "shared-write-#{label}-#{SecureRandom.hex(4)}",
      password: 'password123',
      foaf_address: keypair.fetch('address'),
      foaf_public_key: keypair.fetch('publicKey'),
      foaf_private_key: keypair.fetch('privateKey'),
      foaf_seed_phrase: keypair.fetch('seedPhrase')
    )
  end
end
