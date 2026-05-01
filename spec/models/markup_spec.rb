require 'rails_helper'

RSpec.describe Markup, type: :model do
  describe '#apply_to' do
    it 'adds flat markup and rounds to the nearest nickel' do
      expect(Markup.flat(1.02).apply_to(3.47)).to eq(4.5)
    end

    it 'compounds percent markup against the current price and rounds to the nearest nickel' do
      first_hop = Markup.percent(15).apply_to(3.47)
      second_hop = Markup.percent(10).apply_to(first_hop)

      expect(first_hop).to eq(4.0)
      expect(second_hop).to eq(4.4)
    end

    it 'keeps zero markup neutral' do
      expect(Markup.flat(0).apply_to(12.30)).to eq(12.3)
      expect(Markup.percent(0).apply_to(12.30)).to eq(12.3)
    end
  end
end
