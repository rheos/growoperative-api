require 'rails_helper'

RSpec.describe Api::V1::ItemsController, type: :controller do
  auth_user = "bob"
  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(User.find_by(user_name: auth_user))
  end

  describe '#index' do
    it 'returns successful response' do
      get :index
      expect(response).to be_successful
    end

    let!(:item) {create(:item, user: User.find_by(user_name: "dianna"))}
    it 'returns an item' do
      get :index
      expect(response).to be_successful
      expect(JSON(response.body)["data"][0]["attributes"]["name"]).to eq item.name
    end

    it 'returns an reserved item for chain request member' do
      contract = RequestContract.create(item_id: item.id, inventory_id: item.inventory.first.id, quantity: item.quantity, steps: 1, user_id: User.find_by(user_name: "bob").id)
      request = ItemRequest.create(step: 1, status: :reserved, request_contract_id: contract.id, user_id: User.find_by(user_name: "bob").id, friend_id: User.find_by(user_name: "dianna").id, sent: 0, price: 100)
      item.inventory.first.update(status: :reserved)
      get :index
      expect(response).to be_successful
      expect(JSON(response.body)["data"][0]["attributes"]["name"]).to eq item.name
    end

    it 'do not returns items for member outside of chain request ' do
      auth_user = "barry"
      expect(response).to be_successful
      expect(response.body).to eq ""
    end
  end

  describe '#create' do
    user = User.find_by(user_name: "dianna")
    it 'receiving invalid params and returns an errors' do
      post :create, params: {item: {
        user_id: user.id, 
        quantity: "NaN", 
        category_id: Category.first.id, 
        name: "test", 
        grade_id: Grade.first.id, price: 100, date_available: DateTime.now, item_unit_id: ItemUnit.first.id, organic: true 
      }}
      expect(response).not_to be_successful
      expect(JSON(response.body)).to eq "quantity" => ["is not a number"]
    end

    it 'receiving good params and returns an item' do
      post :create, params: {item: {
        user_id: user.id, 
        quantity: 100, 
        category_id: Category.first.id, 
        name: "test", 
        grade_id: Grade.first.id, price: 100, date_available: DateTime.now, item_unit_id: ItemUnit.first.id, organic: true 
      }}
      expect(response).to be_successful
      expect(JSON(response.body)["data"]["id"]).to eq Inventory.last.id
    end
    
    #params.require(:item).permit(:user_id, :quantity, 
    #:category_id, :item_name_id, :name, :grade_id, :price, 
    #:date_available, :item_unit_id, :unit, :created_at, :organic)
  end

  describe '#update' do
    user = User.find_by(user_name: "dianna")
    describe 'update item' do
      it 'receiving invalid params and returns an errors' do
        post :create, params: {item: {
          user_id: user.id, 
          quantity: 100, 
          category_id: Category.first.id, 
          name: "test", 
          grade_id: Grade.first.id, price: 100, date_available: DateTime.now, item_unit_id: ItemUnit.first.id, organic: true 
        }}

        patch :update, params: {item: {
          quantity: "NaN", 
        }, id: Inventory.last.id}
        expect(response).not_to be_successful
        expect(JSON(response.body)).to eq "quantity" => ["is not a number"]
      end

      it 'receiving good params and returns an item' do
        post :create, params: {item: {
          user_id: user.id, 
          quantity: 100, 
          category_id: Category.first.id, 
          name: "test", 
          grade_id: Grade.first.id, price: 100, date_available: DateTime.now, item_unit_id: ItemUnit.first.id, organic: true 
        }}

        post :update, params: {item: {
          name: "not_test",
          quantity: 100,
        }, id: Inventory.last.id}
        expect(JSON(response.body)["data"]["attributes"]["name"]).to eq "not_test"
      end
      
      #def item_params
        #params.require(:item).permit(:user_id, :quantity, :category_id, :item_name_id, :name, :grade_id, :price, :date_available, :item_unit_id, :unit, :created_at, :organic)
      #end
    end

    describe 'update gellery' do
      #def inventory_avatar_params
        #params.permit({inventory_avatars: [], source_images: []})
      #end
    end

    describe 'update status' do
      #def inventory_status_params
        #params.require(:inventory).permit(:status)
      #end
    end
  end
end
