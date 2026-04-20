# frozen_string_literal: true

# Foaf::AuditService — extracts the row-building and per-trustline reconcile
# logic that was originally inline in DebugController. Used by both the
# (unauth) /v1/debug/foaf/* endpoints and the (auth) /v1/foaf/* endpoints
# so end-user reads don't have to go through DebugController.
module Foaf
  module AuditService
    extend self

    # Reconcile data for a single trustline.
    # Returns the same row shape as the bulk /v1/debug/foaf/reconcile.
    def reconcile_trustline(trustline)
      user_a = User.find(trustline.user_a_id)
      user_b = User.find(trustline.user_b_id)

      row = {
        trustline_id: trustline.id,
        user_a: user_a.user_name,
        user_b: user_b.user_name,
        app: {
          credit_limit_a_to_b: trustline.credit_limit_a_to_b.to_f,
          credit_limit_b_to_a: trustline.credit_limit_b_to_a.to_f,
          balance: trustline.current_balance.to_f,
        },
        foaf: nil,
        match: nil,
        discrepancies: [],
      }

      unless user_a.foaf_address.present?
        row[:discrepancies] << { field: "identity", error: "#{user_a.user_name} has no FOAF address" }
        row[:match] = false
        return row
      end

      client = Foaf::Client.new
      networks = client.networks
      unless networks&.any?
        row[:discrepancies] << { field: "network", error: "No FOAF network found" }
        row[:match] = false
        return row
      end
      network_address = networks.first["address"]

      foaf_trustlines = client.user_trustlines(
        network_address: network_address,
        user_address: user_a.foaf_address,
      )
      unless foaf_trustlines
        row[:discrepancies] << { field: "api", error: "FOAF API call failed" }
        row[:match] = false
        return row
      end

      foaf_tl = foaf_trustlines.find { |ft| ft["counterParty"] == user_b.foaf_address }
      unless foaf_tl
        row[:discrepancies] << { field: "trustline", error: "Not found in FOAF" }
        row[:match] = false
        return row
      end

      # Map FOAF fields back to app semantics
      foaf_limit_a_to_b = foaf_tl["received"]
      foaf_limit_b_to_a = foaf_tl["given"]
      foaf_balance = -foaf_tl["balance"]

      row[:foaf] = {
        credit_limit_a_to_b: foaf_limit_a_to_b,
        credit_limit_b_to_a: foaf_limit_b_to_a,
        balance: foaf_balance,
        raw: { given: foaf_tl["given"], received: foaf_tl["received"], balance: foaf_tl["balance"] },
      }

      if trustline.credit_limit_a_to_b.to_f != foaf_limit_a_to_b
        row[:discrepancies] << { field: "credit_limit_a_to_b", app: trustline.credit_limit_a_to_b.to_f, foaf: foaf_limit_a_to_b }
      end
      if trustline.credit_limit_b_to_a.to_f != foaf_limit_b_to_a
        row[:discrepancies] << { field: "credit_limit_b_to_a", app: trustline.credit_limit_b_to_a.to_f, foaf: foaf_limit_b_to_a }
      end
      if trustline.current_balance.to_f != foaf_balance
        row[:discrepancies] << { field: "balance", app: trustline.current_balance.to_f, foaf: foaf_balance }
      end

      row[:match] = row[:discrepancies].empty?
      row
    end

    # Returns AuditLedgerRow-shaped event log for one trustline.
    # `viewer` is the current user (used to decide which side of a credloop
    # cycle to surface as "the other party").
    def events_for_trustline(trustline, viewer: nil)
      user_a = User.find(trustline.user_a_id)
      user_b = User.find(trustline.user_b_id)

      unless user_a.foaf_address.present? && user_b.foaf_address.present?
        return { rows: [], warning: "One or both users have no FOAF address" }
      end

      client = Foaf::Client.new
      networks = client.networks
      return { error: "No FOAF network found" } unless networks&.any?
      network_address = networks.first["address"]

      events = client.user_events(
        network_address: network_address,
        user_address: user_a.foaf_address,
      ) || []
      relevant = events.select { |e| e["counterParty"] == user_b.foaf_address }

      rows = []

      # Dedupe TrustlineUpdate pairs (shadow mode emits two events per logical
      # bilateral update, one from each side, with given/received swapped).
      seen_update_keys = Set.new

      relevant.each do |e|
        case e["type"]
        when "Transfer"
          rows << build_transfer_row(e, trustline, user_a, user_b)
        when "TrustlineUpdate"
          raw_given = e["creditlineGiven"].to_f
          raw_received = e["creditlineReceived"].to_f
          norm_given = e["direction"] == "received" ? raw_received : raw_given
          norm_received = e["direction"] == "received" ? raw_given : raw_received
          key = [e["timestamp"], norm_given, norm_received]
          next if seen_update_keys.include?(key)
          seen_update_keys << key
          rows << build_trustline_update_row(e, trustline, user_a, user_b)
        end
      end

      tl_events = client.trustline_events(
        network_address: network_address,
        user_address: user_a.foaf_address,
        counter_party_address: user_b.foaf_address,
      ) || []
      tl_events.each do |e|
        next unless e["type"] == "BalanceUpdate"
        parent = e["parentOp"]
        next unless parent && parent["from"] == parent["to"]
        rows << build_credloop_row(e, parent, trustline, user_a, user_b, viewer)
      end

      rows.sort_by! { |r| [r[:transaction][:created_at], r[:transaction][:id]] }

      running = 0.0
      rows.each do |row|
        tx = row[:transaction]
        row[:balance_before] = running
        # Zero-amount rows (trustline limit updates) are balance-neutral.
        # Anything with a real amount — including record_debt / record_receipt
        # adjustments — moves the balance by `value` in the transfer's direction.
        if tx[:amount].to_f == 0
          tx[:balance_after] = running
        else
          delta = tx[:_direction] == "sent" ? tx[:amount] : -tx[:amount]
          running += delta
          tx[:balance_after] = running
        end
        tx.delete(:_direction)
      end

      { rows: rows.reverse }
    end

    private

    def parse_extra_data(data)
      return {} if data.blank?
      return data if data.is_a?(Hash)
      JSON.parse(data)
    rescue JSON::ParserError
      {}
    end

    def build_credloop_row(event, parent, trustline, user_a, user_b, viewer = nil)
      path = parent["path"] || []
      loop_value = parent["value"].to_f
      from_addr = event["from"]

      viewer ||= user_a
      viewer_addr = viewer.foaf_address
      counterparty_addr = (viewer.id == user_a.id) ? user_b.foaf_address : user_a.foaf_address

      inner = path.size > 1 && path.first == path.last ? path[0..-2] : path
      idx = inner.index(viewer_addr)
      other_addr = nil
      if idx
        prev_addr = inner[(idx - 1) % inner.size]
        next_addr = inner[(idx + 1) % inner.size]
        other_addr = (prev_addr == counterparty_addr) ? next_addr : prev_addr
      end
      other_user = other_addr && User.find_by(foaf_address: other_addr)
      other_name = other_user&.user_name || "another user"
      other_trustline_id = other_user && Trustline.between_users(viewer, other_user).first&.id

      direction = from_addr == user_a.foaf_address ? "sent" : "received"

      {
        transaction: {
          id: event["blockNumber"].to_i,
          trustline_id: trustline.id,
          amount: loop_value,
          description: "Offset by your balance with #{other_name}",
          transaction_type: "credloop",
          initiated_by_id: nil,
          originating_request_id: nil,
          order_id: nil,
          balance_after: 0.0,
          is_reversed: false,
          created_at: Time.at(event["timestamp"].to_i).iso8601,
          initiated_by_name: nil,
          order_label: nil,
          path_info: { hops: path, other_user: other_name, other_trustline_id: other_trustline_id },
          _direction: direction,
        },
        balance_before: 0.0,
        source_classification: "credloop",
        balance_mismatch: false,
        missing_linkage: false,
      }
    end

    def build_transfer_row(event, trustline, user_a, user_b)
      extra = parse_extra_data(event["extraData"])
      is_credloop = extra["credloop_cancellation"].present? || (event["extraData"].to_s.include?("credloop_cancellation"))
      is_adjustment = extra["operation"] == "adjustment"
      order_id = extra["order_id"]
      order_label = extra["order_label"]
      description = extra["description"] || (is_credloop ? "Credit loop cancellation" : nil)

      classification = if is_credloop
        "credloop"
      elsif is_adjustment
        "adjustment"
      elsif order_id
        "order_settlement"
      else
        "direct_payment"
      end

      transaction_type = if is_adjustment
        "adjustment"
      elsif order_id
        "settlement"
      else
        "payment"
      end

      path = event["path"]
      initiator = event["direction"] == "sent" ? user_a : user_b

      {
        transaction: {
          id: event["blockNumber"].to_i,
          trustline_id: trustline.id,
          amount: event["value"].to_f,
          description: description,
          transaction_type: transaction_type,
          initiated_by_id: initiator.id,
          originating_request_id: nil,
          order_id: order_id,
          balance_after: 0.0,
          is_reversed: false,
          created_at: Time.at(event["timestamp"].to_i).iso8601,
          initiated_by_name: initiator.user_name,
          order_label: order_label,
          path_info: path.is_a?(Array) && path.size > 2 ? { hops: path } : nil,
          _direction: event["direction"],
        },
        balance_before: 0.0,
        source_classification: classification,
        balance_mismatch: false,
        missing_linkage: false,
      }
    end

    def build_trustline_update_row(event, trustline, user_a, user_b)
      raw_given = event["creditlineGiven"].to_f
      raw_received = event["creditlineReceived"].to_f
      if event["direction"] == "received"
        given = raw_received
        received = raw_given
      else
        given = raw_given
        received = raw_received
      end
      initiator = event["direction"] == "sent" ? user_a : user_b

      {
        transaction: {
          id: event["blockNumber"].to_i,
          trustline_id: trustline.id,
          amount: 0.0,
          description: "Limits updated (given: $#{given}, received: $#{received})",
          transaction_type: "adjustment",
          initiated_by_id: initiator.id,
          originating_request_id: nil,
          order_id: nil,
          balance_after: 0.0,
          is_reversed: false,
          created_at: Time.at(event["timestamp"].to_i).iso8601,
          initiated_by_name: initiator.user_name,
          order_label: nil,
          path_info: nil,
          _direction: event["direction"],
        },
        balance_before: 0.0,
        source_classification: "adjustment",
        balance_mismatch: false,
        missing_linkage: false,
      }
    end
  end
end
