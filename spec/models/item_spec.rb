require 'rails_helper'

RSpec.describe Item, type: :model do
  it 'allows grade to be omitted' do
    item = build(:item, grade: nil)

    expect(item).to be_valid
  end
end
