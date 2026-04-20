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
  end
end
