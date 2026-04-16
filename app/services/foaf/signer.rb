# frozen_string_literal: true

# Isolated signing module — will be replaced with actual wallet signing later.
# Phase 1 (custodial): generates deterministic addresses from user data.
# No real secp256k1 yet (Rails backend is Ruby 2.7, eth gem needs 3.0+).
# When Rails upgrades to Ruby 3+, swap this for real key generation.
#
# IMPORTANT: This entire module is swappable. App code calls Foaf::Signer
# and doesn't know or care how signing happens underneath.

require "digest"
require "securerandom"

module Foaf
  module Signer
    module_function

    # Get the user's FOAF address.
    def address_for(user)
      ensure_keypair!(user)
      user.foaf_address
    end

    # Generate and store an address for a user if they don't have one.
    # Phase 1: deterministic from user_id + secret, not real secp256k1.
    def ensure_keypair!(user)
      return if user.foaf_address.present?

      # Deterministic address derived from user identity + app secret
      seed = "#{user.id}:#{user.user_name}:#{Rails.application.secrets.secret_key_base}"
      address = "0x" + Digest::SHA256.hexdigest(seed)[0..39]
      public_key = "04" + Digest::SHA256.hexdigest("pub:#{seed}") + Digest::SHA256.hexdigest("pub2:#{seed}")

      user.update!(
        foaf_address: address,
        foaf_public_key: public_key,
        foaf_private_key: nil  # no real private key in Phase 1
      )
    end

    # Sign a payload. Phase 1: no-op (FOAF doesn't enforce signatures yet).
    def sign(_user, _payload)
      nil
    end
  end
end
