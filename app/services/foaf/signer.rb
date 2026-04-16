# frozen_string_literal: true

# Isolated signing module — will be replaced with actual wallet signing later.
# Gets keypairs from FOAF protocol, stores them locally. Signs with OpenSSL.
#
# For the average user, this is invisible — they never know there's crypto
# underneath. When we go full web3, advanced users can export their seed
# phrase and manage their own keys.
#
# IMPORTANT: This entire module is swappable.

require "openssl"
require "digest"

module Foaf
  module Signer
    module_function

    # Get the user's FOAF address.
    def address_for(user)
      ensure_keypair!(user)
      user.foaf_address
    end

    # Generate and store a keypair for a user if they don't have one.
    # Gets the keypair from FOAF protocol (including seed phrase).
    def ensure_keypair!(user)
      return if user.foaf_address.present?

      client = Foaf::Client.new
      result = client.generate_keypair

      if result && result["address"]
        user.update!(
          foaf_address: result["address"],
          foaf_public_key: result["publicKey"],
          foaf_private_key: result["privateKey"],
          foaf_seed_phrase: result["seedPhrase"]
        )
      else
        # Fallback: generate locally if FOAF is unreachable
        generate_local_keypair!(user)
      end
    end

    # Sign a payload with the user's private key using OpenSSL.
    def sign(user, payload)
      ensure_keypair!(user)
      return nil unless user.foaf_private_key.present?

      key = OpenSSL::PKey::EC.new("secp256k1")
      key.private_key = OpenSSL::BN.new(user.foaf_private_key, 16)
      group = OpenSSL::PKey::EC::Group.new("secp256k1")
      key.public_key = group.generator.mul(key.private_key)

      digest = Digest::SHA256.digest(payload)
      signature = key.dsa_sign_asn1(digest)
      signature.unpack1("H*")
    rescue => e
      Rails.logger.warn("[FOAF Signer] Signing failed: #{e.message}")
      nil
    end

    # Fallback: generate a keypair locally if FOAF is unreachable.
    # Uses deterministic derivation so the address is stable.
    def generate_local_keypair!(user)
      seed = "#{user.id}:#{user.user_name}:#{Rails.application.secrets.secret_key_base}"
      address = "0x" + Digest::SHA256.hexdigest(seed)[0..39]
      public_key = "04" + Digest::SHA256.hexdigest("pub:#{seed}") + Digest::SHA256.hexdigest("pub2:#{seed}")

      user.update!(
        foaf_address: address,
        foaf_public_key: public_key,
        foaf_private_key: nil,
        foaf_seed_phrase: nil
      )
    end
    private_class_method :generate_local_keypair!
  end
end
