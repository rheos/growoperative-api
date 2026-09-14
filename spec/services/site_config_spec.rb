require 'rails_helper'

RSpec.describe SiteConfig do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe '.for' do
    it 'returns defaults when subnet is nil' do
      expect(SiteConfig.for(nil)).to eq(SiteConfig::DEFAULTS)
    end

    it 'returns defaults when subnet has no config rows' do
      subnet = create(:subnet)
      expect(SiteConfig.for(subnet)).to eq(SiteConfig::DEFAULTS)
    end

    it 'merges the latest config version over defaults' do
      subnet = create(:subnet)
      create(:subnet_config, subnet: subnet, version: 1, config: { 'multi_role' => true })
      create(:subnet_config, subnet: subnet, version: 2, config: { 'multi_role' => false, 'demo_mode' => true })

      result = SiteConfig.for(subnet)
      expect(result[:multi_role]).to eq(false)
      expect(result[:demo_mode]).to eq(true)
      expect(result[:chain_limit]).to eq(SiteConfig::DEFAULTS[:chain_limit])
    end

    it 'returns symbolized keys regardless of storage' do
      subnet = create(:subnet)
      create(:subnet_config, subnet: subnet, version: 1, config: { 'multi_role' => false })

      result = SiteConfig.for(subnet)
      expect(result).to have_key(:multi_role)
    end
  end

  describe '.defaults' do
    it 'returns a duplicate so callers cannot mutate the constant' do
      copy = SiteConfig.defaults
      copy[:multi_role] = :mutated
      expect(SiteConfig::DEFAULTS[:multi_role]).not_to eq(:mutated)
    end

    it 'defaults currency to CAD' do
      expect(SiteConfig::DEFAULTS[:currency]).to eq('CAD')
    end
  end

  describe '.permit_flags' do
    it 'accepts a known currency and drops unknown keys' do
      allowed = SiteConfig.permit_flags(
        currency: 'eur',
        multi_role: false,
        evil_key: 'nope'
      )
      expect(allowed).to eq(currency: 'EUR', multi_role: false)
    end

    it 'drops an unknown currency code so the default is preserved' do
      expect(SiteConfig.permit_flags(currency: 'XXX')).to eq({})
    end
  end

  describe '.invalid_currency?' do
    it 'is false when currency is omitted or valid' do
      expect(SiteConfig.invalid_currency?({})).to eq(false)
      expect(SiteConfig.invalid_currency?(currency: 'EUR')).to eq(false)
      expect(SiteConfig.invalid_currency?(currency: '')).to eq(false)
    end

    it 'is true when an explicit code is not in the catalog' do
      expect(SiteConfig.invalid_currency?(currency: 'XXX')).to eq(true)
    end
  end

  describe '.normalize_currency' do
    it 'upcases a supported code' do
      expect(SiteConfig.normalize_currency('eur')).to eq('EUR')
    end

    it 'rejects an unsupported code' do
      expect(SiteConfig.normalize_currency('XXX')).to be_nil
    end

    it 'accepts Mexican peso and Costa Rican colon' do
      expect(SiteConfig.normalize_currency('mxn')).to eq('MXN')
      expect(SiteConfig.normalize_currency('crc')).to eq('CRC')
    end
  end
end
