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
end
