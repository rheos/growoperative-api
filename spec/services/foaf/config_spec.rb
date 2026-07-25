require 'rails_helper'

RSpec.describe Foaf::Config, skip_hooks: true do
  around do |example|
    previous_current = ENV['FOAF_WRITE_ENABLED']
    previous_legacy = ENV['FOAF_SHADOW_MODE']
    ENV.delete('FOAF_WRITE_ENABLED')
    ENV.delete('FOAF_SHADOW_MODE')

    example.run
  ensure
    previous_current.nil? ? ENV.delete('FOAF_WRITE_ENABLED') : ENV['FOAF_WRITE_ENABLED'] = previous_current
    previous_legacy.nil? ? ENV.delete('FOAF_SHADOW_MODE') : ENV['FOAF_SHADOW_MODE'] = previous_legacy
  end

  describe '.foaf_write_enabled?' do
    it 'is enabled by the current environment name' do
      ENV['FOAF_WRITE_ENABLED'] = 'true'
      expect(described_class.foaf_write_enabled?).to be(true)
    end

    it 'is enabled by the rollout-compatible legacy environment name' do
      ENV['FOAF_SHADOW_MODE'] = 'true'
      expect(described_class.foaf_write_enabled?).to be(true)
    end

    it 'stays enabled when either rollout variable is true' do
      ENV['FOAF_WRITE_ENABLED'] = 'false'
      ENV['FOAF_SHADOW_MODE'] = 'true'
      expect(described_class.foaf_write_enabled?).to be(true)
    end

    it 'is disabled only when neither rollout variable is true' do
      ENV['FOAF_WRITE_ENABLED'] = 'false'
      ENV['FOAF_SHADOW_MODE'] = 'false'
      expect(described_class.foaf_write_enabled?).to be(false)
    end
  end
end
