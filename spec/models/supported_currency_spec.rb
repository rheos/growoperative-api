require 'rails_helper'

RSpec.describe SupportedCurrency do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe '.catalog' do
    it 'includes builtin CAD even when the table is empty' do
      expect(SupportedCurrency.codes).to include('CAD', 'EUR', 'CRC', 'THB')
    end

    it 'includes a row written through the registry' do
      SupportedCurrency.create!(code: 'php', name: 'Philippine peso', locale: 'en-PH')
      expect(SupportedCurrency.codes).to include('PHP')
      php = SupportedCurrency.catalog.find { |row| row[:code] == 'PHP' }
      expect(php[:name]).to eq('Philippine peso')
      expect(php[:locale]).to eq('en-PH')
    end

    it 'omits a deactivated row' do
      SupportedCurrency.create!(code: 'PHP', name: 'Philippine peso', locale: 'en-PH', active: false)
      expect(SupportedCurrency.codes).not_to include('PHP')
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
