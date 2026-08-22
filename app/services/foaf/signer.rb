# frozen_string_literal: true

# Isolated signing module — will be replaced with actual wallet signing later.
# Gets keypairs from FOAF protocol, stores them locally.
#
# IMPORTANT: This entire module is swappable.

module Foaf
  # Raised when signing cannot proceed and there is no safe path forward:
  # a migrated user reaches the legacy branch with a nulled local key, or a
  # pending user has no local key. There is NO silent nil-signature fallback
  # (EC 5). Custodian-side failures surface as Foaf::Custodian::SigningError.
  class SigningError < StandardError; end

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

    # Sign a payload for a user.
    #
    # Routing (spec R3 / EC 4 — never mix sources for one user):
    #   custody_state == "migrated" -> ALWAYS the shared custodian, even if
    #     FOAF_SHARED_WRITES is false. The local key is nulled post-migration;
    #     the flag gates the START of the cutover, not the continuity after it.
    #   custody_state != "migrated" -> the legacy local-key path.
    #
    # EC 5 fail-fast: no silent nil-signature. A pending user with no local key
    # raises Foaf::SigningError; a custodian failure raises
    # Foaf::Custodian::SigningError. Neither is swallowed, neither falls back.
    #
    # The (user, payload) signature is unchanged so all call sites keep working
    # (FR 13); only the path taken for migrated users differs.
    def sign(user, payload)
      if user.custody_state == "migrated"
        sign_via_custodian(user, payload)
      else
        # Legacy path: local key in DB (only for custody_state != "migrated").
        if user.foaf_private_key.blank?
          raise Foaf::SigningError,
                "no local key and custodian not enabled for user #{user.foaf_id}"
        end

        ensure_keypair!(user)
        Foaf::LedgerSigner.sign(user.foaf_private_key, payload)
      end
    end

    # Route signing to the shared FOAF custodian over HTTPS. The custodian
    # resolves the key from foaf_id (one address per identity); signer_address
    # is forwarded but ignored server-side. Raises Foaf::Custodian::SigningError
    # on a non-2xx or network failure — there is no local-key fallback (EC 5).
    def sign_via_custodian(user, payload)
      provider = Foaf::Custodian::RemoteSignatureProvider.new(
        base_url: ENV.fetch("FOAF_AUTH_URL"),
        service_token: ENV.fetch("FOAF_AUTH_SERVICE_TOKEN_GROWOP"),
        foaf_id: user.foaf_id
      )
      provider.call(user.foaf_address, payload)
    end
  end
end
