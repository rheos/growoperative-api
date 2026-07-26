# frozen_string_literal: true

# Loads canonical user_a-perspective balances for a collection of Rails
# trustline edges. Rails supplies graph membership and IDs; FOAF supplies every
# balance. The network is fetched once and each distinct user_a trustline list
# is fetched once, regardless of the number of edges owned by that user.
module Foaf
  module GraphBalanceReader
    extend self

    def fetch(trustlines)
      edges = trustlines.to_a
      return {} if edges.empty?
      return nil unless edges.all? { |edge| addresses_present?(edge) }

      client = Foaf::Client.new
      networks = client.networks
      return nil unless networks&.any?

      network_address = networks.first["address"]
      rows_by_user_a_id = {}

      edges.group_by(&:user_a_id).each do |user_a_id, owned_edges|
        user_a = owned_edges.first.user_a
        rows = client.user_trustlines(
          network_address: network_address,
          user_address: user_a.foaf_address
        )
        return nil unless rows

        rows_by_user_a_id[user_a_id] = rows.index_by do |row|
          row["counterParty"].to_s.downcase
        end
      end

      edges.each_with_object({}) do |edge, balances|
        row = rows_by_user_a_id.fetch(edge.user_a_id)[edge.user_b.foaf_address.downcase]
        return nil unless row

        balances[edge.id] = Foaf::Balances
          .from_trustline_row(row)
          .fetch(:viewer_balance)
          .to_f
      end
    end

    private

    def addresses_present?(edge)
      edge.user_a.foaf_address.present? && edge.user_b.foaf_address.present?
    end
  end
end
