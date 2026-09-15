require 'rails_helper'

RSpec.describe VariableWeightEstimate do
  describe '.billed_rate' do
    it 'returns the base rate when not on the rail' do
      expect(described_class.billed_rate(10)).to eq(10)
    end

    it 'subtracts the on-the-rail delta' do
      expect(described_class.billed_rate(10, 1.30, on_the_rail: true)).to eq(BigDecimal('8.70'))
    end

    it 'ignores the delta when not on the rail' do
      expect(described_class.billed_rate(10, 1.30, on_the_rail: false)).to eq(10)
    end

    it 'never goes negative' do
      expect(described_class.billed_rate(1, 5, on_the_rail: true)).to eq(0)
    end
  end

  describe '.billed_range' do
    it 'multiplies the rate across the carcass-weight range' do
      low, high = described_class.billed_range(10, 450, 550)
      expect(low).to eq(4500)
      expect(high).to eq(5500)
    end
  end

  describe '.take_home_range' do
    it 'applies the yield factor to carcass weight (~40% loss at 0.6)' do
      low, high = described_class.take_home_range(450, 550, 0.6)
      expect(low).to eq(270)
      expect(high).to eq(330)
    end
  end

  describe '.packaged_rate' do
    it 'is billed_rate / yield — the effective $/lb of take-home meat' do
      # $10/lb carcass at a 0.6 yield ~= $16.67/lb of actual cuts.
      expect(described_class.packaged_rate(10, 0.6).round(2)).to eq(BigDecimal('16.67'))
    end

    it "matches Madrone's ~$13.50 only at a milder ~0.74 yield (not hard-coded)" do
      expect(described_class.packaged_rate(10, 0.74).round(2)).to eq(BigDecimal('13.51'))
    end

    it 'is nil when the yield factor is zero' do
      expect(described_class.packaged_rate(10, 0)).to be_nil
    end
  end
end
