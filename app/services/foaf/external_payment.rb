# frozen_string_literal: true

# Parses public block-explorer URLs pasted into a payment note.
#
# Phase 1 recognizes Polygonscan transaction URLs only. The result is a
# structured pointer stored in FOAF transfer extraData (and Rails path_info)
# so the client can render a styled chip instead of the raw URL. This is
# documentation, not on-chain authentication — we never fetch RPC data here.
#
# Trustline amounts are CAD. A Polygonscan link is treated as USDT unless the
# note names another known ticker. We never copy the CAD amount onto the token.
module Foaf
  class ExternalPayment
    POLYGONSCAN_TX = %r{
      (?:https?://)?(?:www\.|m\.)?polygonscan\.com/tx/(0x[a-fA-F0-9]{64})
    }ix
    NOTE_TOKEN = /\b(USDC|DAI|USDT|BTC|ETH|BITCOIN|ETHEREUM)\b/i
    TOKEN_ALIASES = {
      "BITCOIN" => "BTC",
      "ETHEREUM" => "ETH"
    }.freeze

    def self.parse(text)
      return [] if text.blank?

      token = token_symbol_from(text)
      text.to_s.scan(POLYGONSCAN_TX).flatten.map { |hash|
        normalized = hash.downcase
        {
          "chain" => "polygon",
          "tx_hash" => normalized,
          "explorer_url" => "https://polygonscan.com/tx/#{normalized}",
          "token_symbol" => token
        }
      }.uniq { |payment| payment["tx_hash"] }
    end

    def self.token_symbol_from(text)
      match = text.to_s.match(NOTE_TOKEN)
      return "USDT" unless match

      raw = match[1].upcase
      TOKEN_ALIASES.fetch(raw, raw)
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
