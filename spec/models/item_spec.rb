require 'rails_helper'

RSpec.describe Item, type: :model do
  subject { Item.new user_id: 1, category_id: 1, grade_id: 1, quantity: 1, price: 2, name: 'item' }
  it 'should create an inventory after created' do
    subject.save
    
    expect(subject.inventory.size).to be(1)
    expect(subject.inventory[0].item_id).to be(subject.id)
    expect(subject.inventory[0].quantity).to be(1.0)
    expect(subject.inventory[0].price).to be(2)
  end
end
