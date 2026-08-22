require 'rails_helper'

RSpec.describe Foaf::Signer, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'emits a FOAF-compatible Ethereum personal_sign signature' do
    private_key = '1' * 64
    address = Foaf::LedgerSigner.address(private_key)
    user = User.create!(
      user_name: 'ledger-signer',
      password: 'password123',
      foaf_address: address,
      foaf_private_key: private_key
    )
    payload = '{"network_address":"0xnetwork","value":"4.5"}'

    signature = described_class.sign(user, payload)
    recovered_public_key = Eth::Signature.personal_recover(payload, signature)
    recovered_address = Eth::Util.public_key_to_address(
      Eth::Util.hex_to_bin(recovered_public_key)
    ).to_s

    expect(recovered_address.downcase).to eq(address.downcase)
  end

  # Prompt 10 — per-user signing cutover through the shared custodian.
  # Routing (spec R3 / EC 4): custody_state == "migrated" routes to the custodian
  # ALWAYS (never mix sources for one user); the local key is nulled post-migration
  # so it must never be read again. EC 5: no silent nil-signature fallback.
  describe 'per-user custodian routing (Prompt 10)' do
    let(:payload) { '{"network_address":"0xnetwork","value":"4.5"}' }

    # No ClimateControl gem in this repo (see push_delivery_spec.rb) — save/restore
    # the env vars this path reads by hand, matching config_spec.rb's pattern.
    around do |example|
      keys = %w[FOAF_SHARED_WRITES FOAF_AUTH_URL FOAF_AUTH_SERVICE_TOKEN_GROWOP]
      previous = keys.index_with { |k| ENV[k] }
      ENV['FOAF_AUTH_URL'] = 'https://auth.example.test'
      ENV['FOAF_AUTH_SERVICE_TOKEN_GROWOP'] = 'svc-token'

      example.run
    ensure
      previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    def migrated_user
      # A migrated user has no local private key — it was nulled by the key
      # migration (Prompt 9). foaf_id + foaf_address remain for the custodian.
      User.create!(
        user_name: "migrated-#{SecureRandom.hex(4)}",
        password: 'password123',
        foaf_address: "0x#{'a' * 40}",
        foaf_private_key: nil,
        custody_state: 'migrated'
      )
    end

    def pending_user_with_key
      private_key = '1' * 64
      User.create!(
        user_name: "pending-key-#{SecureRandom.hex(4)}",
        password: 'password123',
        foaf_address: Foaf::LedgerSigner.address(private_key),
        foaf_private_key: private_key,
        custody_state: 'pending'
      )
    end

    def pending_user_without_key
      User.create!(
        user_name: "pending-nokey-#{SecureRandom.hex(4)}",
        password: 'password123',
        foaf_address: "0x#{'b' * 40}",
        foaf_private_key: nil,
        custody_state: 'pending'
      )
    end

    context 'when custody_state is "migrated"' do
      it 'routes to the custodian and NOT the local key when FOAF_SHARED_WRITES=true' do
        ENV['FOAF_SHARED_WRITES'] = 'true'
        provider = instance_double(Foaf::Custodian::RemoteSignatureProvider, call: '0xsig')
        expect(Foaf::Custodian::RemoteSignatureProvider).to receive(:new).and_return(provider)
        expect(Foaf::LedgerSigner).not_to receive(:sign)

        expect(described_class.sign(migrated_user, payload)).to eq('0xsig')
      end

      it 'STILL routes to the custodian when FOAF_SHARED_WRITES=false (EC 4 — never fall back to a nulled local key)' do
        ENV['FOAF_SHARED_WRITES'] = 'false'
        provider = instance_double(Foaf::Custodian::RemoteSignatureProvider, call: '0xsig')
        expect(Foaf::Custodian::RemoteSignatureProvider).to receive(:new).and_return(provider)
        expect(Foaf::LedgerSigner).not_to receive(:sign)

        expect(described_class.sign(migrated_user, payload)).to eq('0xsig')
      end

      it 'forwards the exact payload and foaf address to the custodian' do
        ENV['FOAF_SHARED_WRITES'] = 'true'
        provider = instance_double(Foaf::Custodian::RemoteSignatureProvider)
        user = migrated_user
        expect(Foaf::Custodian::RemoteSignatureProvider).to receive(:new).with(
          base_url: 'https://auth.example.test',
          service_token: 'svc-token',
          foaf_id: user.foaf_id
        ).and_return(provider)
        expect(provider).to receive(:call).with(user.foaf_address, payload).and_return('0xsig')

        described_class.sign(user, payload)
      end

      it 'surfaces a custodian failure as Foaf::Custodian::SigningError (EC 5 — no fallback)' do
        ENV['FOAF_SHARED_WRITES'] = 'true'
        provider = instance_double(Foaf::Custodian::RemoteSignatureProvider)
        allow(Foaf::Custodian::RemoteSignatureProvider).to receive(:new).and_return(provider)
        allow(provider).to receive(:call).and_raise(
          Foaf::Custodian::SigningError, 'custodian unreachable'
        )
        expect(Foaf::LedgerSigner).not_to receive(:sign)

        expect { described_class.sign(migrated_user, payload) }
          .to raise_error(Foaf::Custodian::SigningError)
      end
    end

    context 'when custody_state is "pending"' do
      it 'uses the local key (legacy path still works)' do
        ENV['FOAF_SHARED_WRITES'] = 'true'
        expect(Foaf::Custodian::RemoteSignatureProvider).not_to receive(:new)
        user = pending_user_with_key

        signature = described_class.sign(user, payload)
        recovered_public_key = Eth::Signature.personal_recover(payload, signature)
        recovered_address = Eth::Util.public_key_to_address(
          Eth::Util.hex_to_bin(recovered_public_key)
        ).to_s

        expect(recovered_address.downcase).to eq(user.foaf_address.downcase)
      end

      it 'raises Foaf::SigningError when the local key is nil (EC 5 fail-fast, no silent nil-signature)' do
        ENV['FOAF_SHARED_WRITES'] = 'true'
        expect(Foaf::Custodian::RemoteSignatureProvider).not_to receive(:new)
        expect(Foaf::LedgerSigner).not_to receive(:sign)

        expect { described_class.sign(pending_user_without_key, payload) }
          .to raise_error(Foaf::SigningError, /no local key and custodian not enabled/)
      end
    end
  end
end
