require 'rails_helper'

RSpec.describe SubnetConfig, type: :model do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'is append-only; updating an existing row raises' do
    subnet = create(:subnet)
    cfg = create(:subnet_config, subnet: subnet, version: 1, config: { 'multi_role' => true })

    cfg.config = { 'multi_role' => false }
    expect { cfg.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'requires unique version per subnet' do
    subnet = create(:subnet)
    create(:subnet_config, subnet: subnet, version: 1)
    dup = build(:subnet_config, subnet: subnet, version: 1)
    expect(dup).not_to be_valid
  end

  it 'allows the same version number on different subnets' do
    create(:subnet_config, subnet: create(:subnet), version: 1)
    other = build(:subnet_config, subnet: create(:subnet), version: 1)
    expect(other).to be_valid
  end
end
