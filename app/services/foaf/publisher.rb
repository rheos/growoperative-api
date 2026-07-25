# frozen_string_literal: true

# Publishes GrowOperative trustline operations to FOAF.
#
# Balance-moving operations retain their Rails TrustlineTransaction row as a
# failure buffer until FOAF returns a known successful operation. Publication
# errors are recorded/logged and ReplayWorker resolves unposted rows.

module Foaf
  class Publisher
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
        Rails.logger.warn("[FOAF Publisher] No network found on FOAF")
      end

      @network_address
    end

    # Ensure a user has a FOAF keypair.
    # No registration with FOAF needed — addresses exist by usage, like blockchain.
    def ensure_identity!(user)
      Foaf::Signer.ensure_keypair!(user)
    end

    # Publish a trustline update to FOAF.
    # FOAF uses two-stage accept — we send both sides so it completes immediately.
    def publish_trustline_update(trustline, current_user)
      return unless Foaf::Config.foaf_write_enabled?
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

      unless write_succeeded?(r1)
        Rails.logger.warn("[FOAF Publisher] Trustline proposal failed: #{user_a.user_name} -> #{user_b.user_name} (network=#{@network_address})")
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

      unless write_succeeded?(r2)
        Rails.logger.warn("[FOAF Publisher] Trustline accept failed: #{user_b.user_name} -> #{user_a.user_name}")
        return
      end

      Rails.logger.info("[FOAF Publisher] Published trustline update: #{user_a.user_name} <-> #{user_b.user_name}")
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Trustline publish failed: #{e.message}")
    end

    # Publish a settlement to FOAF.
    #
    # Settlement reduces payer's debt to payee. FOAF's only balance-affecting
    # primitive is `transfer`, which always extends credit (sender becomes
    # more indebted to receiver). To express settlement via transfer, we send
    # payee→payer (making payee more indebted to payer = payer less indebted
    # to payee — same net result). See project_settlement_vs_extension memory.
    def publish_settlement(trustline, amount, payer, payee, description: nil, order: nil, operation: "settlement", metadata: nil, tx_row: nil)
      publish_payment(trustline, amount, payee, payer,
                      description: description, order: order, operation: operation, metadata: metadata, tx_row: tx_row)
    end

    # Publish a payment to FOAF. Honors FOAF's existing credit limits — if the
    # transfer exceeds capacity, FOAF rejects and the publisher logs a warning
    # without affecting the local Rails commit. The proper warn-and-expand UX
    # is tracked in project_settlement_vs_extension memory.
    #
    # When shared writes are enabled, tx_row supplies a deterministic
    # idempotency key and retains the pending-transfer/reconciliation state.
    # When they are disabled this executes the unchanged legacy write path.
    def publish_payment(trustline, amount, from_user, to_user, description: nil, order: nil, operation: "payment", metadata: nil, tx_row: nil)
      return unless Foaf::Config.foaf_write_enabled?
      return unless ensure_network!

      ensure_identity!(from_user)
      ensure_identity!(to_user)

      extra_data = {
        app: "growoperative",
        description: description,
        operation: operation,
        order_id: order&.id,
        order_label: order&.try(:order_label),
        # Preserve the existing wire metadata key during this naming-only
        # rollout so FOAF event consumers see byte-for-byte compatible metadata.
        mirrored_at: (tx_row&.created_at || Time.current).iso8601
      }.merge(metadata || {}).compact.to_json

      if Foaf::Config.shared_writes?
        return publish_shared_payment(
          amount: amount,
          from_user: from_user,
          to_user: to_user,
          extra_data: extra_data,
          tx_row: tx_row
        )
      end

      publish_legacy_payment(
        amount: amount,
        from_user: from_user,
        to_user: to_user,
        extra_data: extra_data,
        tx_row: tx_row
      )
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Payment publish failed: #{e.message}")
    end

    private

    def publish_legacy_payment(amount:, from_user:, to_user:, extra_data:, tx_row:)
      result = @client.create_pending_transfer(
        network_address: @network_address,
        from_address: Foaf::Signer.address_for(from_user),
        to_address: Foaf::Signer.address_for(to_user),
        value: amount.to_f,
        extra_data: extra_data
      )

      unless result && result["id"]
        Rails.logger.warn("[FOAF Publisher] Create pending transfer failed: #{from_user.user_name} -> #{to_user.user_name} ($#{amount})")
        return
      end

      # Auto-confirm since the app already processed the payment
      confirm = @client.confirm_transfer(
        pending_transfer_id: result["id"],
        signer_address: Foaf::Signer.address_for(to_user)
      )

      unless confirm
        Rails.logger.warn("[FOAF Publisher] Confirm transfer failed: PT##{result["id"]} #{from_user.user_name} -> #{to_user.user_name}")
        return
      end

      mark_legacy_posted!(tx_row, confirm) if tx_row

      Rails.logger.info("[FOAF Publisher] Published payment: #{from_user.user_name} -> #{to_user.user_name} ($#{amount})")
    end

    def publish_shared_payment(amount:, from_user:, to_user:, extra_data:, tx_row:)
      from_address = Foaf::Signer.address_for(from_user)
      to_address = Foaf::Signer.address_for(to_user)
      idempotency_key = shared_idempotency_key(tx_row)

      lookup = if tx_row&.foaf_pending_transfer_id
        @client.pending_transfer(
          pending_transfer_id: tx_row.foaf_pending_transfer_id
        )
      else
        @client.pending_transfer_by_idempotency_key(
          idempotency_key: idempotency_key
        )
      end

      if write_succeeded?(lookup)
        return resolve_shared_pending(
          lookup.fetch("data"),
          amount: amount,
          from_address: from_address,
          to_address: to_address,
          idempotency_key: idempotency_key,
          tx_row: tx_row
        )
      end

      unless lookup["status"] == 404
        record_write_result!(tx_row, "ambiguous_create", lookup)
        return
      end

      created = @client.create_pending_transfer(
        network_address: @network_address,
        from_address: from_address,
        to_address: to_address,
        value: amount.to_f,
        extra_data: extra_data,
        idempotency_key: idempotency_key
      )

      if write_succeeded?(created)
        return resolve_shared_pending(
          created.fetch("data"),
          amount: amount,
          from_address: from_address,
          to_address: to_address,
          idempotency_key: idempotency_key,
          tx_row: tx_row
        )
      end

      if created["outcome"] == "ambiguous"
        record_write_result!(tx_row, "ambiguous_create", created)
        return reconcile_ambiguous_create(
          amount: amount,
          from_address: from_address,
          to_address: to_address,
          idempotency_key: idempotency_key,
          tx_row: tx_row
        )
      end

      record_write_result!(tx_row, "rejected", created)
      nil
    end

    def reconcile_ambiguous_create(amount:, from_address:, to_address:, idempotency_key:, tx_row:)
      lookup = @client.pending_transfer_by_idempotency_key(
        idempotency_key: idempotency_key
      )
      return unless write_succeeded?(lookup)

      resolve_shared_pending(
        lookup.fetch("data"),
        amount: amount,
        from_address: from_address,
        to_address: to_address,
        idempotency_key: idempotency_key,
        tx_row: tx_row
      )
    end

    def resolve_shared_pending(pending, amount:, from_address:, to_address:, idempotency_key:, tx_row:)
      unless pending_matches?(
        pending,
        amount: amount,
        from_address: from_address,
        to_address: to_address,
        idempotency_key: idempotency_key
      )
        record_write_result!(
          tx_row,
          "rejected",
          "ok" => false,
          "status" => 409,
          "outcome" => "rejected",
          "body" => pending.to_json,
          "error" => "Reconciled pending transfer does not match the intended write"
        )
        return
      end

      pending_id = pending.fetch("id")
      case pending["status"]
      when "confirmed"
        operation_id = pending["operation"]
        if operation_id
          mark_posted!(tx_row, pending, pending_transfer_id: pending_id)
          return pending
        end

        record_write_result!(
          tx_row,
          "ambiguous_confirm",
          "ok" => false,
          "status" => 200,
          "outcome" => "ambiguous",
          "body" => pending.to_json,
          "error" => "Confirmed transfer has no operation id",
          pending_transfer_id: pending_id
        )
        return
      when "rejected", "cancelled"
        record_write_result!(
          tx_row,
          "rejected",
          "ok" => false,
          "status" => 409,
          "outcome" => "rejected",
          "body" => pending.to_json,
          "error" => "Pending transfer is #{pending["status"]}",
          pending_transfer_id: pending_id
        )
        return
      end

      record_write_result!(
        tx_row,
        "pending",
        { "ok" => true, "status" => 200, "outcome" => "success", "body" => pending.to_json },
        pending_transfer_id: pending_id
      )

      confirmed = @client.confirm_transfer(
        pending_transfer_id: pending_id,
        signer_address: to_address
      )
      if write_succeeded?(confirmed)
        mark_posted!(
          tx_row,
          confirmed.fetch("data"),
          pending_transfer_id: pending_id
        )
        return confirmed.fetch("data")
      end

      if confirmed["outcome"] == "ambiguous" || confirmed["status"] == 409
        record_write_result!(
          tx_row,
          "ambiguous_confirm",
          confirmed,
          pending_transfer_id: pending_id
        )
        return reconcile_ambiguous_confirm(
          pending_transfer_id: pending_id,
          amount: amount,
          from_address: from_address,
          to_address: to_address,
          idempotency_key: idempotency_key,
          tx_row: tx_row
        )
      end

      record_write_result!(
        tx_row,
        "rejected",
        confirmed,
        pending_transfer_id: pending_id
      )
      nil
    end

    def reconcile_ambiguous_confirm(pending_transfer_id:, amount:, from_address:, to_address:, idempotency_key:, tx_row:)
      lookup = @client.pending_transfer(
        pending_transfer_id: pending_transfer_id
      )
      unless write_succeeded?(lookup)
        record_write_result!(
          tx_row,
          "ambiguous_confirm",
          lookup,
          pending_transfer_id: pending_transfer_id
        )
        return
      end

      resolve_reconciled_confirm(
        lookup.fetch("data"),
        amount: amount,
        from_address: from_address,
        to_address: to_address,
        idempotency_key: idempotency_key,
        tx_row: tx_row
      )
    end

    # A reconciliation read must not issue another confirm in the same call:
    # "pending" proves no apply yet but the original response may still be in
    # flight. The replay worker will read again before an idempotent retry.
    def resolve_reconciled_confirm(pending, amount:, from_address:, to_address:, idempotency_key:, tx_row:)
      unless pending_matches?(
        pending,
        amount: amount,
        from_address: from_address,
        to_address: to_address,
        idempotency_key: idempotency_key
      )
        return record_write_result!(
          tx_row,
          "rejected",
          "ok" => false,
          "status" => 409,
          "outcome" => "rejected",
          "body" => pending.to_json,
          "error" => "Reconciled pending transfer does not match the intended write"
        )
      end

      if pending["status"] == "confirmed" && pending["operation"]
        return mark_posted!(
          tx_row,
          pending,
          pending_transfer_id: pending.fetch("id")
        )
      end

      state = %w[rejected cancelled].include?(pending["status"]) ? "rejected" : "ambiguous_confirm"
      record_write_result!(
        tx_row,
        state,
        "ok" => false,
        "status" => 200,
        "outcome" => state == "rejected" ? "rejected" : "ambiguous",
        "body" => pending.to_json,
        "error" => "Reconciled transfer status is #{pending["status"]}",
        pending_transfer_id: pending.fetch("id")
      )
    end

    def pending_matches?(pending, amount:, from_address:, to_address:, idempotency_key:)
      pending["idempotencyKey"] == idempotency_key &&
        pending["from"].to_s.casecmp?(from_address.to_s) &&
        pending["to"].to_s.casecmp?(to_address.to_s) &&
        BigDecimal(pending["value"].to_s) == BigDecimal(amount.to_s)
    rescue ArgumentError
      false
    end

    def shared_idempotency_key(tx_row)
      if tx_row
        "growoperative:trustline_transaction:#{tx_row.id}"
      else
        "growoperative:adhoc:#{SecureRandom.uuid}"
      end
    end

    def write_succeeded?(result)
      if Foaf::Config.shared_writes?
        result.is_a?(Hash) && result["outcome"] == "success"
      else
        result.present?
      end
    end

    def mark_legacy_posted!(tx_row, confirm_response)
      tx_row.update!(
        foaf_operation_id: confirm_response["operation"],
        foaf_posted_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Failed to mark tx #{tx_row.id} posted: #{e.message}")
    end

    def record_write_result!(tx_row, state, result, pending_transfer_id: nil)
      return unless tx_row

      tx_row.update!(
        foaf_pending_transfer_id: pending_transfer_id || tx_row.foaf_pending_transfer_id,
        foaf_write_state: state,
        foaf_write_error: result.slice("status", "outcome", "body", "error").to_json
      )
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Failed to record tx #{tx_row.id} state=#{state}: #{e.message}")
    end

    # Confirm response shape: { status, transfer, operation, totalFees }.
    # `operation` is FOAF's Operation#id. Stash it alongside posted_at so
    # the retry worker knows to skip this row.
    def mark_posted!(tx_row, confirm_response, pending_transfer_id: nil)
      operation_id = confirm_response["operation"] ||
                     confirm_response.dig("transfer", "operation")
      raise "FOAF confirm response has no operation id" unless operation_id

      return confirm_response unless tx_row

      tx_row.update!(
        foaf_operation_id: operation_id,
        foaf_pending_transfer_id: pending_transfer_id || tx_row.foaf_pending_transfer_id,
        foaf_posted_at: Time.current,
        foaf_write_state: "posted",
        foaf_write_error: nil
      )
      confirm_response
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Failed to mark tx #{tx_row&.id || "adhoc"} posted: #{e.message}")
      nil
    end

    public

    # Compare FOAF state with local state for a trustline.
    def reconcile_trustline(trustline)
      return unless Foaf::Config.foaf_write_enabled?
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

      # Map raw FOAF state into the app's canonical user_a perspective. This is
      # the same mapping used by Foaf::AuditService.
      local_balance = trustline.balance_for(user_a).to_f
      foaf_balance = -foaf_tl["balance"].to_f
      discrepancies[:balance] = { local: local_balance, foaf: foaf_balance } if local_balance != foaf_balance

      local_given = trustline.credit_limit_b_to_a.to_f
      foaf_given = foaf_tl["given"].to_f
      discrepancies[:given] = { local: local_given, foaf: foaf_given } if local_given != foaf_given

      local_received = trustline.credit_limit_a_to_b.to_f
      foaf_received = foaf_tl["received"].to_f
      discrepancies[:received] = { local: local_received, foaf: foaf_received } if local_received != foaf_received

      if discrepancies.any?
        Rails.logger.warn("[FOAF Publisher] DISCREPANCY on trustline #{trustline.id} " \
                          "(#{user_a.user_name} <-> #{user_b.user_name}): #{discrepancies}")
        discrepancies
      else
        nil
      end
    rescue StandardError => e
      Rails.logger.warn("[FOAF Publisher] Reconcile failed: #{e.message}")
      { error: e.message }
    end

  end
end
