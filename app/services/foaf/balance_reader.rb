# frozen_string_literal: true

# Foaf::BalanceReader — viewer-perspective trustline state sourced from FOAF.
#
# Single FOAF call per user. Joins the returned trustlines against the user's
# active Rails Trustline rows for non-balance metadata (id, established_date,
# notes, etc.). Returns rows already flipped into the app's balance/limit
# convention:
#
#   viewer_balance     = -foaf_tl["balance"]   (positive = viewer owes)
#   my_credit_limit    =  foaf_tl["received"]  (viewer's borrow cap)
#   their_credit_limit =  foaf_tl["given"]     (counterparty's borrow cap)
#
# `fetch` return values:
#   [...rows]  — normal
#   []         — user has no active Rails trustlines (skip FOAF)
#   nil        — FOAF unreachable, no network, or user lacks foaf_address
module Foaf
  module BalanceReader
    extend self

    def fetch(user)
      app_trustlines = user.trustlines.active.includes(:user_a, :user_b).to_a
      return [] if app_trustlines.empty?

      return nil unless user.foaf_address.present?

      client = Foaf::Client.new
      networks = client.networks
      return nil unless networks&.any?

      foaf_tls = client.user_trustlines(
        network_address: networks.first["address"],
        user_address: user.foaf_address,
      )
      return nil unless foaf_tls

      app_by_foaf_addr = {}
      app_trustlines.each do |tl|
        counterparty = tl.other_user(user)
        next unless counterparty.foaf_address.present?
        app_by_foaf_addr[counterparty.foaf_address] = { trustline: tl, counterparty: counterparty }
      end

      foaf_tls.each_with_object([]) do |foaf_tl, rows|
        entry = app_by_foaf_addr[foaf_tl["counterParty"]]
        next unless entry

        rows << entry.merge(
          Foaf::Balances.from_trustline_row(foaf_tl).transform_values(&:to_f)
        )
      end
    end
  end
end
