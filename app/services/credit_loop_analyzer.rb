# frozen_string_literal: true

# Consumer-side indexer for FOAF credit-loop cancellations.
#
# Pulls raw operations + events from the FOAF protocol and reconstructs the
# debt cycle per cancellation, resolving addresses to local User names and
# local Trustline IDs. All analytics work happens here — FOAF is treated as
# external state (blockchain-analog), we never write back to it.
#
# Long-term this logic will likely migrate to an external explorer service
# (scan.foaf.io). For now it ships in-app so superusers can inspect loops
# from the admin panel.

class CreditLoopAnalyzer
  class << self
    def list(limit: 20)
      client = Foaf::Client.new
      network_address = first_network_address(client)
      return [] unless network_address

      # Fetch a wide slice of recent transfer ops and filter client-side.
      # Credloops are a subset of transfers whose inputs.from == inputs.to.
      result = client.operations(
        network_address: network_address,
        type: "transfer",
        limit: 200,
      )
      return [] unless result

      operations = result["operations"] || []
      credloops = operations.select { |op| credloop?(op) }.first(limit)

      # Resolve all addresses once (batch).
      addrs = credloops.flat_map { |op| (op.dig("inputs", "path") || []) }.uniq
      names = resolve_names(addrs)

      credloops.map { |op| summarize(op, names) }
    end

    def detail(operation_id)
      client = Foaf::Client.new
      op_data = client.operation(operation_id: operation_id)
      raise "Operation not found" unless op_data
      raise "Operation ##{operation_id} is not a credit-loop cancellation" unless credloop?(op_data)

      build_report(op_data, client)
    end

    private

    def first_network_address(client)
      networks = client.networks
      networks&.any? ? networks.first["address"] : nil
    end

    def credloop?(op)
      return false unless op["operation_type"] == "transfer"
      inputs = op["inputs"] || {}
      from = inputs["from"]
      to = inputs["to"]
      from.present? && from == to
    end

    def summarize(op, names)
      inputs = op["inputs"] || {}
      transfer_path = inputs["path"] || []
      debt_cycle = debt_cycle_from_transfer_path(transfer_path)
      {
        operation_id: op["id"],
        detected_at: op["created_at"],
        cancellable_amount: inputs["value"].to_f,
        hop_count: debt_cycle.empty? ? 0 : debt_cycle.size - 1,
        path: debt_cycle.map { |addr| { address: addr, name: names[addr] } },
      }
    end

    def build_report(op_data, client)
      inputs = op_data["inputs"] || {}
      transfer_path = inputs["path"] || []
      value = inputs["value"].to_f
      debt_cycle = debt_cycle_from_transfer_path(transfer_path)

      balance_events = (op_data["events"] || []).select { |e| e["event_type"] == "BalanceUpdate" }
      event_by_pair = balance_events.index_by { |e| [e["from_address"], e["to_address"]] }

      all_addrs = debt_cycle.uniq
      users_by_addr = User.where(foaf_address: all_addrs).index_by(&:foaf_address)
      names_by_addr = users_by_addr.transform_values(&:user_name)

      # Resolve local Trustline per pair (once per unique pair).
      trustline_by_pair = {}
      debt_cycle.each_cons(2) do |debtor_addr, creditor_addr|
        pair = [debtor_addr, creditor_addr].sort
        next if trustline_by_pair.key?(pair)
        a = users_by_addr[debtor_addr]
        b = users_by_addr[creditor_addr]
        trustline_by_pair[pair] = a && b ? Trustline.between_users(a, b).first : nil
      end

      hops = debt_cycle.each_cons(2).map do |debtor_addr, creditor_addr|
        # Cancellation transfer direction is creditor -> debtor (extending FOAF
        # credit in the opposite direction of the pre-existing debt).
        update_event = event_by_pair[[creditor_addr, debtor_addr]]
        post_canonical = update_event&.dig("balance").to_f
        post_debt = post_debt_magnitude(post_canonical, debtor_addr, creditor_addr)
        tl = trustline_by_pair[[debtor_addr, creditor_addr].sort]

        {
          debtor: { address: debtor_addr, name: names_by_addr[debtor_addr] },
          creditor: { address: creditor_addr, name: names_by_addr[creditor_addr] },
          trustline_id: tl&.id,
          pre_debt: post_debt + value,
          post_debt: post_debt,
        }
      end

      {
        operation_id: op_data["id"],
        detected_at: op_data["created_at"],
        cancellable_amount: value,
        hop_count: hops.size,
        path: debt_cycle.map { |addr| { address: addr, name: names_by_addr[addr] } },
        hops: hops,
        triggered_by: fetch_trigger(op_data, client),
      }
    end

    def fetch_trigger(op_data, client)
      network_address = op_data["currency_network_address"]
      return nil unless network_address

      # Look a short way back — most loops cascade directly after a transfer.
      result = client.operations(
        network_address: network_address,
        before_id: op_data["id"],
        limit: 20,
      )
      return nil unless result

      prior = (result["operations"] || []).find { |op| !credloop?(op) }
      return nil unless prior

      prior_inputs = prior["inputs"] || {}
      from_addr = prior_inputs["from"]
      to_addr = prior_inputs["to"]
      users = User.where(foaf_address: [from_addr, to_addr].compact).index_by(&:foaf_address)

      {
        operation_id: prior["id"],
        created_at: prior["created_at"],
        operation_type: prior["operation_type"],
        from: { address: from_addr, name: users[from_addr]&.user_name },
        to: { address: to_addr, name: users[to_addr]&.user_name },
        value: prior_inputs["value"]&.to_f,
      }
    end

    # Build the debt cycle [A, B, C, D, A] from the stored transfer path
    # [A, D, C, B, A]. CredloopDetector.build_transfer_path reverses the
    # middle segment; we undo that here.
    def debt_cycle_from_transfer_path(transfer_path)
      return [] if transfer_path.nil? || transfer_path.size < 3
      first = transfer_path.first
      middle = transfer_path[1..-2]
      [first] + middle.reverse + [first]
    end

    # FOAF canonical balance convention (see CredloopService.build_debt_edges):
    # positive balance = user_b owes user_a, where user_a_address is
    # lexicographically less than user_b_address.
    def post_debt_magnitude(canonical_balance, debtor_addr, creditor_addr)
      user_b_addr = [debtor_addr, creditor_addr].max
      signed = debtor_addr == user_b_addr ? canonical_balance : -canonical_balance
      signed > 0 ? signed : 0.0
    end

    def resolve_names(addresses)
      addrs = addresses.compact.uniq
      return {} if addrs.empty?
      User.where(foaf_address: addrs).pluck(:foaf_address, :user_name).to_h
    end
  end
end
