# frozen_string_literal: true

# Aggregates the Trustlines summary cards from the same viewer-perspective FOAF
# rows used by the index endpoint. One BalanceReader call performs one FOAF
# user-trustlines fetch; no per-trustline protocol requests are made here.
module Foaf
  module BalanceSummary
    extend self

    def fetch(user)
      rows = Foaf::BalanceReader.fetch(user)
      return nil if rows.nil?

      owed = rows.sum(0.to_d) do |row|
        balance = row.fetch(:viewer_balance).to_d
        balance.positive? ? balance : 0.to_d
      end
      owed_to_me = rows.sum(0.to_d) do |row|
        balance = row.fetch(:viewer_balance).to_d
        balance.negative? ? balance.abs : 0.to_d
      end
      available = rows.sum(0.to_d) do |row|
        balance = row.fetch(:viewer_balance).to_d
        row.fetch(:my_credit_limit).to_d - [balance, 0.to_d].max
      end

      {
        total_trustlines: rows.length,
        total_credit_owed: owed,
        total_credit_owed_to_me: owed_to_me,
        net_credit_position: owed_to_me - owed,
        available_credit: available
      }
    end
  end
end
