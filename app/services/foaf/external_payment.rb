# frozen_string_literal: true

# Parses public block-explorer URLs pasted into a payment note.
#
# Phase 1 recognizes Polygonscan transaction URLs only. The result is a
# structured pointer stored in FOAF transfer extraData (and Rails path_info)
# so the client can render a styled chip instead of the raw URL. This is
# documentation, not on-chain authentication — we never fetch RPC data here.
module Foaf
  class ExternalPayment
    POLYGONSCAN_TX = %r{
      (?:https?://)?(?:www\.|m\.)?polygonscan\.com/tx/(0x[a-fA-F0-9]{64})
    }ix

    def self.parse(text)
      return [] if text.blank?

      text.to_s.scan(POLYGONSCAN_TX).flatten.map { |hash|
        normalized = hash.downcase
        {
          "chain" => "polygon",
          "tx_hash" => normalized,
          "explorer_url" => "https://polygonscan.com/tx/#{normalized}"
        }
      }.uniq { |payment| payment["tx_hash"] }
    end

    def self.metadata_for(text)
      payments = parse(text)
      return {} if payments.empty?

      if payments.one?
        { "external_payment" => payments.first }
      else
        { "external_payments" => payments }
      end
    end

    # Merge parsed pointers into an existing extraData / path_info hash.
    # Empty parse is a no-op so callers can always wrap.
    def self.merge_into(hash, text)
      extra = metadata_for(text)
      return hash if extra.empty?

      (hash || {}).deep_stringify_keys.merge(extra)
    end
  end
end
