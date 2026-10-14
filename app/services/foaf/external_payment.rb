# frozen_string_literal: true

# Parses public block-explorer URLs pasted into a payment note.
#
# Recognizes Polygonscan and Etherscan transaction URLs. The result is a
# structured pointer stored in FOAF transfer extraData (and Rails path_info)
# so the client can render a styled chip instead of the raw URL. This is
# documentation, not on-chain authentication — we never fetch RPC data here.
#
# Trustline amounts are CAD. A Polygonscan link is treated as USDT unless the
# note names USDC or DAI. BTC/ETH are other chains, not Polygon tickers.
# An Etherscan link takes USDT, USDC, DAI or ETH from the note and otherwise
# carries no token, since a mainnet transfer is as likely ETH as a stable.
# We never copy the CAD amount onto the token.
module Foaf
  class ExternalPayment
    EXPLORERS = [
      { chain: "polygon", host: "polygonscan.com", tokens: /\b(USDC|DAI|USDT)\b/i, default_token: "USDT" },
      { chain: "ethereum", host: "etherscan.io", tokens: /\b(USDC|DAI|USDT|ETH)\b/i, default_token: nil }
    ].freeze

    # The lookbehind keeps testnet subdomains (sepolia.etherscan.io,
    # amoy.polygonscan.com) from matching as mainnet.
    EXPLORER_TX = %r{
      (?<![\w.-])(?:https?://)?(?:www\.|m\.)?(#{EXPLORERS.map { |e| Regexp.escape(e[:host]) }.join("|")})/tx/(0x[a-fA-F0-9]{64})
    }ix

    def self.parse(text)
      return [] if text.blank?

      text.to_s.scan(EXPLORER_TX).filter_map { |host, hash|
        explorer = EXPLORERS.find { |e| e[:host] == host.downcase }
        next unless explorer

        normalized = hash.downcase
        {
          "chain" => explorer[:chain],
          "tx_hash" => normalized,
          "explorer_url" => "https://#{explorer[:host]}/tx/#{normalized}",
          "token_symbol" => token_symbol_from(text, explorer[:chain])
        }.compact
      }.uniq { |payment| payment.values_at("chain", "tx_hash") }
    end

    def self.token_symbol_from(text, chain = "polygon")
      explorer = EXPLORERS.find { |e| e[:chain] == chain }
      return nil unless explorer

      match = text.to_s.match(explorer[:tokens])
      match ? match[1].upcase : explorer[:default_token]
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
