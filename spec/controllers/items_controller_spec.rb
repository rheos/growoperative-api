require 'rails_helper'

RSpec.describe Api::V1::ItemsController, type: :controller do
  let(:user)      { User.create!(user_name: 'items_create_user', password: 'password123') }
  let(:item_unit) { ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592) }
  let(:category)  { Category.create!(category_name: 'greens', default_unit: item_unit, kind: :produce, default_node_price: 1.0) }
  let(:grade)     { Grade.create!(name: 'A', value: 30) }

  before do
    allow(controller).to receive(:authenticate!).and_return(true)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'POST #create' do
    it 'creates an item when apply_first_hop_markup is omitted' do
      post :create, params: {
        item: {
          quantity: 10,
          category_id: category.id,
          name: 'Carrot',
          grade_id: grade.id,
          price: 5,
          item_unit_id: item_unit.id,
          description: 'Fresh carrots'
        }
      }

      expect(response).to have_http_status(:ok)
      inventory = Inventory.last
      expect(inventory).to be_present
      expect(inventory.apply_first_hop_markup).to eq(false)
      expect(inventory.description).to eq('Fresh carrots')
    end

    it 'respects apply_first_hop_markup when provided' do
      post :create, params: {
        item: {
          quantity: 10,
          category_id: category.id,
          name: 'Carrot',
          grade_id: grade.id,
          price: 5,
          item_unit_id: item_unit.id,
          description: 'Fresh carrots'
        },
        apply_first_hop_markup: true
      }

      expect(response).to have_http_status(:ok)
      expect(Inventory.last.apply_first_hop_markup).to eq(true)
    end
  end
end
