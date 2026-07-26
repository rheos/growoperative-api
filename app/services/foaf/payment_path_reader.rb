# frozen_string_literal: true

# Maps FOAF's authoritative capacity path back onto GrowOperative users.
#
# Rails keeps relationship metadata and durable per-hop transaction rows, but
# it no longer performs its own graph traversal or balance/capacity math.
module Foaf
  class PaymentPathReader
    Result = Struct.new(:path, :capacity, :error, keyword_init: true) do
      def available?
        error.nil?
      end

      def found?
        available? && path.present?
      end
    end

    def self.fetch(from_user:, to_user:, amount:, max_hops:, client: Foaf::Client.new)
      new(
        from_user: from_user,
        to_user: to_user,
        amount: amount,
        max_hops: max_hops,
        client: client
      ).fetch
    end

    def initialize(from_user:, to_user:, amount:, max_hops:, client:)
      @from_user = from_user
      @to_user = to_user
      @amount_input = amount
      @max_hops_input = max_hops
      @client = client
    end

    def fetch
      amount = BigDecimal(@amount_input.to_s)
      max_hops = Integer(@max_hops_input)
      return unavailable("Sender has no FOAF address") unless @from_user.foaf_address.present?
      return unavailable("Receiver has no FOAF address") unless @to_user.foaf_address.present?
      return no_path if @from_user.id == @to_user.id
      return unavailable("Invalid maximum hop count") unless max_hops.positive?

      networks = @client.networks
      return unavailable("FOAF network unavailable") unless networks&.any?

      path_info = @client.max_capacity_path_info(
        network_address: networks.first.fetch("address"),
        from_address: @from_user.foaf_address,
        to_address: @to_user.foaf_address
      )
      return unavailable("FOAF path unavailable") unless path_info.is_a?(Hash)

      capacity = BigDecimal(path_info.fetch("capacity").to_s)
      addresses = Array(path_info["path"])
      return no_path(capacity) if capacity < amount || addresses.empty?
      return no_path(capacity) if addresses.length - 1 > max_hops
      return unavailable("FOAF returned an invalid path") unless valid_endpoints?(addresses)

      users = map_users(addresses)
      return unavailable("FOAF path contains an unknown GrowOperative identity") unless users
      unless users.first.id == @from_user.id && users.last.id == @to_user.id
        return unavailable("FOAF path identities do not match the requested users")
      end
      return unavailable("FOAF path is missing Rails trustline metadata") unless rails_edges_exist?(users)

      Result.new(path: users, capacity: capacity)
    rescue KeyError, ArgumentError => e
      unavailable("Invalid FOAF path response: #{e.message}")
    rescue StandardError => e
      Rails.logger.warn("[FOAF PaymentPathReader] #{e.class}: #{e.message}")
      unavailable("FOAF path unavailable")
    end

    private

    def valid_endpoints?(addresses)
      addresses.first.to_s.casecmp?(@from_user.foaf_address.to_s) &&
        addresses.last.to_s.casecmp?(@to_user.foaf_address.to_s)
    end

    def map_users(addresses)
      normalized = addresses.map { |address| address.to_s.downcase }
      by_address = User
        .where("LOWER(foaf_address) IN (?)", normalized)
        .index_by { |user| user.foaf_address.downcase }
      users = normalized.map { |address| by_address[address] }
      users if users.all?
    end

    def rails_edges_exist?(users)
      users.each_cons(2).all? do |left, right|
        Trustline.active.between_users(left, right).exists?
      end
    end

    def no_path(capacity = BigDecimal("0"))
      Result.new(path: nil, capacity: capacity)
    end

    def unavailable(message)
      Result.new(path: nil, capacity: BigDecimal("0"), error: message)
    end
  end
end
