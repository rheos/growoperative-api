# frozen_string_literal: true

# Isolated signing module — will be replaced with actual wallet signing later.
# Gets keypairs from FOAF protocol, stores them locally.
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
    # Reloads from DB first to avoid stale in-memory objects generating
    # duplicate keys in the same request.
    def ensure_keypair!(user)
      user.reload if user.foaf_address.nil? && user.persisted?
      return if user.foaf_address.present?

      client = Foaf::Client.new
      result = client.generate_keypair

      if result && result["address"]
        user.update_columns(
          foaf_address: result["address"],
          foaf_public_key: result["publicKey"],
          foaf_private_key: result["privateKey"],
          foaf_seed_phrase: result["seedPhrase"]
        )
        # Update the in-memory object too
        user.foaf_address = result["address"]
        user.foaf_public_key = result["publicKey"]
        user.foaf_private_key = result["privateKey"]
        user.foaf_seed_phrase = result["seedPhrase"]
      else
        Rails.logger.warn("[FOAF Signer] Failed to get keypair from FOAF for #{user.user_name}")
      end
    end

    # Sign a payload with the user's private key.
    def sign(user, payload)
      ensure_keypair!(user)
      return nil unless user.foaf_private_key.present?

      ec = OpenSSL::PKey::EC.new("secp256k1")
      ec.private_key = OpenSSL::BN.new(user.foaf_private_key, 16)
      group = OpenSSL::PKey::EC::Group.new("secp256k1")
      ec.public_key = group.generator.mul(ec.private_key)

      digest = Digest::SHA256.digest(payload)
      signature = ec.dsa_sign_asn1(digest)
      signature.unpack1("H*")
    rescue => e
      Rails.logger.warn("[FOAF Signer] Signing failed: #{e.message}")
      nil
    end
  end
end
