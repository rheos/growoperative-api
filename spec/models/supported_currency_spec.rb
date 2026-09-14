require 'rails_helper'

RSpec.describe SupportedCurrency do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe '.catalog' do
    it 'includes builtin CAD even when the table is empty' do
      expect(SupportedCurrency.codes).to include('CAD', 'EUR', 'CRC')
    end

    it 'includes a row written through the registry' do
      SupportedCurrency.create!(code: 'thb', name: 'Thai baht', locale: 'th-TH')
      expect(SupportedCurrency.codes).to include('THB')
      thb = SupportedCurrency.catalog.find { |row| row[:code] == 'THB' }
      expect(thb[:name]).to eq('Thai baht')
      expect(thb[:locale]).to eq('th-TH')
    end

    it 'omits a deactivated row' do
      SupportedCurrency.create!(code: 'THB', name: 'Thai baht', locale: 'th-TH', active: false)
      expect(SupportedCurrency.codes).not_to include('THB')
    end
  end

  describe 'validations' do
    it 'upcases and requires a 3-letter code' do
      row = SupportedCurrency.create!(code: 'ars', name: 'Argentine peso', locale: 'es-AR')
      expect(row.code).to eq('ARS')
      dup = SupportedCurrency.new(code: 'ARS', name: 'Peso', locale: 'es-AR')
      expect(dup).not_to be_valid
    end
  end
end
