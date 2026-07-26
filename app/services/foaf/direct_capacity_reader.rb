# frozen_string_literal: true

# Direct-edge payment capacity sourced from FOAF's protocol path API.
#
# The protocol returns the direct path first whenever that trustline has
# non-negative capacity. Requiring the exact [sender, receiver] path prevents a
# "direct" Rails operation from silently routing through other FOAF edges.
module Foaf
  class DirectCapacityReader
    Result = Struct.new(:capacity, :error, keyword_init: true) do
      def available?
        error.nil?
      end

      def sufficient_for?(amount)
        available? && capacity >= BigDecimal(amount.to_s)
      end
    end

    def self.fetch(from_user:, to_user:, client: Foaf::Client.new)
      new(from_user: from_user, to_user: to_user, client: client).fetch
    end

    def initialize(from_user:, to_user:, client:)
      @from_user = from_user
      @to_user = to_user
      @client = client
    end

    def fetch
      return unavailable("Sender has no FOAF address") unless @from_user.foaf_address.present?
      return unavailable("Receiver has no FOAF address") unless @to_user.foaf_address.present?

      networks = @client.networks
      return unavailable("FOAF network unavailable") unless networks&.any?

      path_info = @client.max_capacity_path_info(
        network_address: networks.first.fetch("address"),
        from_address: @from_user.foaf_address,
        to_address: @to_user.foaf_address
      )
      return unavailable("FOAF capacity unavailable") unless path_info.is_a?(Hash)

      path = Array(path_info["path"])
      direct_path = [@from_user.foaf_address, @to_user.foaf_address]
      capacity = if same_path?(path, direct_path)
        BigDecimal(path_info.fetch("capacity").to_s)
      else
        BigDecimal("0")
      end

      Result.new(capacity: capacity)
    rescue KeyError, ArgumentError => e
      unavailable("Invalid FOAF capacity response: #{e.message}")
    rescue StandardError => e
      Rails.logger.warn("[FOAF DirectCapacityReader] #{e.class}: #{e.message}")
      unavailable("FOAF capacity unavailable")
    end

    private

    def same_path?(actual, expected)
      actual.size == expected.size &&
        actual.zip(expected).all? { |left, right| left.to_s.casecmp?(right.to_s) }
    end

    def unavailable(message)
      Result.new(capacity: BigDecimal("0"), error: message)
    end
  end
end
