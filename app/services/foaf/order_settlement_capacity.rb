# frozen_string_literal: true

# Ensures a direct order-settlement transfer has protocol-authoritative
# capacity before Rails records the buffered payment operation.
#
# FOAF remains responsible for all balance/capacity math. Rails only:
# - retains relationship metadata and the durable limit-update outbox,
# - asks FOAF for the direct-path capacity,
# - increases the viewer's FOAF-reported limit by FOAF's reported shortfall,
# - publishes that limit snapshot, then verifies capacity with FOAF again.
module Foaf
  class OrderSettlementCapacity
    class Error < StandardError; end

    def self.ensure!(
      from_user:,
      to_user:,
      amount:,
      capacity_reader: Foaf::DirectCapacityReader,
      balance_reader: Foaf::BalanceReader
    )
      new(
        from_user: from_user,
        to_user: to_user,
        amount: amount,
        capacity_reader: capacity_reader,
        balance_reader: balance_reader
      ).ensure!
    end

    def initialize(from_user:, to_user:, amount:, capacity_reader:, balance_reader:)
      @from_user = from_user
      @to_user = to_user
      @amount = BigDecimal(amount.to_s)
      @capacity_reader = capacity_reader
      @balance_reader = balance_reader
    end

    def ensure!
      raise Error, "Settlement amount must be positive" unless @amount.positive?

      trustline = Trustline.between_users(@from_user, @to_user).first
      if trustline.nil?
        trustline = create_trustline!
        publish_limit!(trustline)
      end

      capacity = fetch_capacity!
      return trustline if capacity.sufficient_for?(@amount)

      state = fetch_foaf_state!(trustline)
      shortfall = @amount - capacity.capacity
      expand_limit!(trustline, decimal(state.fetch(:my_credit_limit)) + shortfall)
      publish_limit!(trustline)

      verified = fetch_capacity!
      unless verified.sufficient_for?(@amount)
        raise Error,
              "FOAF capacity remained insufficient after the durable limit update"
      end

      trustline
    end

    private

    def create_trustline!
      Trustline.create!(
        user_a: @from_user,
        user_b: @to_user,
        credit_limit_a_to_b: @amount,
        credit_limit_b_to_a: 0,
        current_balance: 0,
        is_active: true
      )
    end

    def fetch_capacity!
      result = @capacity_reader.fetch(from_user: @from_user, to_user: @to_user)
      raise Error, result.error unless result.available?

      result
    end

    def fetch_foaf_state!(trustline)
      rows = @balance_reader.fetch(@from_user)
      raise Error, "FOAF trustline state unavailable" if rows.nil?

      row = rows.find { |candidate| candidate[:trustline].id == trustline.id }
      raise Error, "Trustline was not returned by FOAF" unless row

      row
    end

    def expand_limit!(trustline, new_limit)
      if @from_user.id == trustline.user_a_id
        trustline.update!(credit_limit_a_to_b: new_limit)
      else
        trustline.update!(credit_limit_b_to_a: new_limit)
      end
    end

    def publish_limit!(trustline)
      Foaf::LedgerHooks.after_trustline_save(trustline, @from_user)
    end

    def decimal(value)
      BigDecimal(value.to_s)
    end
  end
end
