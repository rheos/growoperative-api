require 'rails_helper'

RSpec.describe Item, type: :model do
  describe 'variable-weight (per_weight) listings' do
    let(:meat) { Category.find_by(category_name: 'Meat') }

    def build_share(attrs = {})
      build(:item, {
        category: meat,
        pricing_basis: :per_weight,
        price: 10,
        sale_unit_label: 'side',
        est_weight_min: 450,
        est_weight_max: 550,
        cut_yield_factor: 0.6,
        on_the_rail_available: true,
        on_the_rail_delta: 1.30
      }.merge(attrs))
    end

    it 'seeds a Meat category with a pound default unit' do
      expect(meat).to be_present
      expect(meat.default_unit&.item_symbol).to eq('lb')
    end

    it 'is valid with an estimate range' do
      expect(build_share).to be_valid
    end

    it 'requires an estimate range' do
      expect(build_share(est_weight_min: nil)).not_to be_valid
    end

    it 'rejects a reversed range (min > max)' do
      expect(build_share(est_weight_min: 600)).not_to be_valid
    end

    it 'rejects a yield factor above 1' do
      expect(build_share(cut_yield_factor: 1.5)).not_to be_valid
    end

    it 'rejects a negative on-the-rail delta' do
      expect(build_share(on_the_rail_delta: -1)).not_to be_valid
    end

    it 'leaves per_unit listings unconstrained by the weight fields' do
      expect(build(:item, pricing_basis: :per_unit, est_weight_min: nil)).to be_valid
    end

    it 'computes the billed estimate range from rate x weight' do
      expect(build_share.billed_estimate_range.map(&:to_i)).to eq([4500, 5500])
    end

    it 'applies the on-the-rail delta to the billed rate' do
      expect(build_share.billed_rate(on_the_rail: true)).to eq(BigDecimal('8.70'))
    end

    it 'computes take-home weight from the yield factor' do
      expect(build_share.take_home_estimate_range.map(&:to_i)).to eq([270, 330])
    end

    it 'defaults new listings to per_unit' do
      expect(build(:item).pricing_basis).to eq('per_unit')
    end
  end
end
