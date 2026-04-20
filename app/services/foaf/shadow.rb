# frozen_string_literal: true

# Shadow mode: mirrors trustline operations to FOAF protocol.
# The existing code remains authoritative. FOAF receives a copy.
# Discrepancies are logged for investigation.
#
# All shadow calls are fire-and-forget — failures are logged, never raised.
# The app must never break because FOAF is down or returns an error.

module Foaf
  class Shadow
    def initialize
      @client = Foaf::Client.new
    end

    # Ensure the default network exists on FOAF.
    # Re-fetches every time — the network address can change after a reset.
    def ensure_network!
      networks = @client.networks
      if networks&.any?
        @network_address = networks.first["address"]
      else
        @network_address = nil
        Rails.logger.warn("[FOAF Shadow] No network found on FOAF")
      end

      @network_address
    end

    # Ensure a user has a FOAF keypair.
    # No registration with FOAF needed — addresses exist by usage, like blockchain.
    def ensure_identity!(user)
      Foaf::Signer.ensure_keypair!(user)
    end

    # Mirror a trustline update to FOAF.
    # FOAF uses two-stage accept — we send both sides so it completes immediately.
    def mirror_trustline_update(trustline, current_user)
      return unless Foaf::Config.shadow_mode?
      return unless ensure_network!

      user_a = User.find(trustline.user_a_id)
      user_b = User.find(trustline.user_b_id)
      ensure_identity!(user_a)
      ensure_identity!(user_b)

      addr_a = Foaf::Signer.address_for(user_a)
      addr_b = Foaf::Signer.address_for(user_b)

      # CRITICAL: semantic mapping (see foaf-protocol skill)
      # App credit_limit_a_to_b (A can owe B) = FOAF creditline_received (from A's perspective)
      # App credit_limit_b_to_a (B can owe A) = FOAF creditline_given (from A's perspective)

      # First call: user_a proposes
      r1 = @client.update_trustline(
        network_address: @network_address,
        creditor_address: addr_a,
        debtor_address: addr_b,
        creditline_given: trustline.credit_limit_b_to_a,
        creditline_received: trustline.credit_limit_a_to_b
      )

      unless r1
        Rails.logger.warn("[FOAF Shadow] Trustline proposal failed: #{user_a.user_name} -> #{user_b.user_name} (network=#{@network_address})")
        return
      end

      # Second call: user_b accepts (with matching terms)
      r2 = @client.update_trustline(
        network_address: @network_address,
        creditor_address: addr_b,
        debtor_address: addr_a,
        creditline_given: trustline.credit_limit_a_to_b,
        creditline_received: trustline.credit_limit_b_to_a
      )

      unless r2
        Rails.logger.warn("[FOAF Shadow] Trustline accept failed: #{user_b.user_name} -> #{user_a.user_name}")
        return
      end

      Rails.logger.info("[FOAF Shadow] Mirrored trustline update: #{user_a.user_name} <-> #{user_b.user_name}")
    rescue StandardError => e
      Rails.logger.warn("[FOAF Shadow] Trustline mirror failed: #{e.message}")
    end

    # Mirror a settlement to FOAF.
    #
    # Settlement reduces payer's debt to payee. FOAF's only balance-affecting
    # primitive is `transfer`, which always extends credit (sender becomes
    # more indebted to receiver). To express settlement via transfer, we send
    # payee→payer (making payee more indebted to payer = payer less indebted
    # to payee — same net result). See project_settlement_vs_extension memory.
    def mirror_settlement(trustline, amount, payer, payee, description: nil, order: nil, operation: "settlement")
      mirror_payment(trustline, amount, payee, payer,
                      description: description, order: order, operation: operation)
    end

    # Mirror a payment to FOAF. Honors FOAF's existing credit limits — if the
    # transfer exceeds capacity, FOAF rejects and the shadow logs a warning
    # without affecting the local Rails commit. The proper warn-and-expand UX
    # is tracked in project_settlement_vs_extension memory.
    def mirror_payment(trustline, amount, from_user, to_user, description: nil, order: nil, operation: "payment")
      return unless Foaf::Config.shadow_mode?
      return unless ensure_network!

      ensure_identity!(from_user)
      ensure_identity!(to_user)

      extra_data = {
        app: "growoperative",
        description: description,
        operation: operation,
        order_id: order&.id,
        order_label: order&.try(:order_label),
        mirrored_at: Time.current.iso8601
      }.compact.to_json

      result = @client.create_pending_transfer(
        network_address: @network_address,
        from_address: Foaf::Signer.address_for(from_user),
        to_address: Foaf::Signer.address_for(to_user),
        value: amount.to_f,
        extra_data: extra_data
      )

      unless result && result["id"]
        Rails.logger.warn("[FOAF Shadow] Create pending transfer failed: #{from_user.user_name} -> #{to_user.user_name} ($#{amount})")
        return
      end

      # Auto-confirm since the app already processed the payment
      confirm = @client.confirm_transfer(pending_transfer_id: result["id"])

      unless confirm
        Rails.logger.warn("[FOAF Shadow] Confirm transfer failed: PT##{result["id"]} #{from_user.user_name} -> #{to_user.user_name}")
        return
      end

      Rails.logger.info("[FOAF Shadow] Mirrored payment: #{from_user.user_name} -> #{to_user.user_name} ($#{amount})")
    rescue StandardError => e
      Rails.logger.warn("[FOAF Shadow] Payment mirror failed: #{e.message}")
    end

    # Compare FOAF state with local state for a trustline.
    def reconcile_trustline(trustline)
      return unless Foaf::Config.shadow_mode?
      return unless ensure_network!

      user_a = User.find(trustline.user_a_id)
      return unless user_a.foaf_address.present?

      foaf_trustlines = @client.user_trustlines(
        network_address: @network_address,
        user_address: user_a.foaf_address
      )
      return unless foaf_trustlines

      user_b = User.find(trustline.user_b_id)
      foaf_tl = foaf_trustlines.find { |t| t["counterParty"] == user_b.foaf_address }
      return { error: "Trustline not found in FOAF" } unless foaf_tl

      discrepancies = {}

      local_balance = trustline.balance_for(user_a).to_f
      foaf_balance = foaf_tl["balance"].to_f
      discrepancies[:balance] = { local: local_balance, foaf: foaf_balance } if local_balance != foaf_balance

      local_given = trustline.credit_limit_a_to_b.to_f
      foaf_given = foaf_tl["given"].to_f
      discrepancies[:given] = { local: local_given, foaf: foaf_given } if local_given != foaf_given

      local_received = trustline.credit_limit_b_to_a.to_f
      foaf_received = foaf_tl["received"].to_f
      discrepancies[:received] = { local: local_received, foaf: foaf_received } if local_received != foaf_received

      if discrepancies.any?
        Rails.logger.warn("[FOAF Shadow] DISCREPANCY on trustline #{trustline.id} " \
                          "(#{user_a.user_name} <-> #{user_b.user_name}): #{discrepancies}")
        discrepancies
      else
        nil
      end
    rescue StandardError => e
      Rails.logger.warn("[FOAF Shadow] Reconcile failed: #{e.message}")
      { error: e.message }
    end

  end
end
