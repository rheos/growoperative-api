# frozen_string_literal: true

require "rails_helper"

RSpec.describe Foaf::ExternalPayment do
  let(:hash) { "0x#{'ab' * 32}" }
  let(:canonical) { "https://polygonscan.com/tx/#{hash}" }

  describe ".parse" do
    it "returns an empty array for blank text" do
      expect(described_class.parse(nil)).to eq([])
      expect(described_class.parse("")).to eq([])
      expect(described_class.parse("   ")).to eq([])
    end

    it "leaves a plain note untouched" do
      expect(described_class.parse("groceries, 5/13 order")).to eq([])
    end

    it "extracts a Polygonscan transaction URL" do
      expect(described_class.parse("Paid #{canonical}")).to eq([
        {
          "chain" => "polygon",
          "tx_hash" => hash,
          "explorer_url" => canonical,
          "token_symbol" => "USDT"
        }
      ])
    end

    it "accepts http, www, mobile host, trailing slash, and query string" do
      variants = [
        "http://polygonscan.com/tx/#{hash}",
        "https://www.polygonscan.com/tx/#{hash}/",
        "https://m.polygonscan.com/tx/#{hash}?utm=1",
        "polygonscan.com/tx/#{hash}#eventlog"
      ]

      variants.each do |text|
        expect(described_class.parse(text)).to eq([
          {
            "chain" => "polygon",
            "tx_hash" => hash,
            "explorer_url" => canonical,
            "token_symbol" => "USDT"
          }
        ]), text
      end
    end

    it "lowercases the hash in the canonical explorer URL" do
      mixed = "0x#{'AB' * 32}"
      parsed = described_class.parse("https://polygonscan.com/tx/#{mixed}")
      expect(parsed.first["tx_hash"]).to eq(hash)
      expect(parsed.first["explorer_url"]).to eq(canonical)
    end

    it "rejects a truncated hash" do
      expect(described_class.parse("https://polygonscan.com/tx/0xabc")).to eq([])
    end

    it "dedupes the same hash pasted twice" do
      text = "#{canonical} and again #{canonical.upcase.sub('POLYGONSCAN', 'polygonscan')}"
      expect(described_class.parse(text).size).to eq(1)
    end

    it "returns every distinct hash" do
      other = "0x#{'cd' * 32}"
      text = "#{canonical} #{canonical.sub(hash, other)}"
      expect(described_class.parse(text).map { |p| p["tx_hash"] }).to eq([hash, other])
    end

    it "defaults Polygonscan notes to USDT, unless the note names USDC or DAI" do
      expect(described_class.parse(canonical).first["token_symbol"]).to eq("USDT")
      expect(described_class.parse("USDC #{canonical}").first["token_symbol"]).to eq("USDC")
      expect(described_class.parse("BTC #{canonical}").first["token_symbol"]).to eq("USDT")
      expect(described_class.parse("paid in ethereum #{canonical}").first["token_symbol"]).to eq("USDT")
    end
  end

  describe ".metadata_for" do
    it "returns an empty hash when nothing matched" do
      expect(described_class.metadata_for("cash")).to eq({})
    end

    it "uses external_payment for a single URL" do
      expect(described_class.metadata_for(canonical)).to eq(
        "external_payment" => {
          "chain" => "polygon",
          "tx_hash" => hash,
          "explorer_url" => canonical,
          "token_symbol" => "USDT"
        }
      )
    end

    it "uses external_payments for multiple URLs" do
      other = "0x#{'cd' * 32}"
      meta = described_class.metadata_for(
        "https://polygonscan.com/tx/#{hash} https://polygonscan.com/tx/#{other}"
      )
      expect(meta.keys).to eq(["external_payments"])
      expect(meta["external_payments"].map { |p| p["tx_hash"] }).to eq([hash, other])
    end
  end

  describe ".merge_into" do
    it "is a no-op when the note has no explorer URL" do
      base = { payment_request: { requested_by_name: "alex" } }
      expect(described_class.merge_into(base, "groceries")).to eq(base)
    end

    it "stringifies existing keys and adds the parsed pointer" do
      merged = described_class.merge_into(
        { payment_request: { requested_by_name: "alex" } },
        canonical
      )
      expect(merged["payment_request"]).to eq("requested_by_name" => "alex")
      expect(merged["external_payment"]["tx_hash"]).to eq(hash)
    end
  end
end
