require 'rails_helper'

RSpec.describe Api::V1::ItemsController, type: :controller do
  before(:each) do
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(User.find_by(user_name: RSpec.current_user))
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

      RSpec.set_user("barry")
    end

    it 'do not returns items for member outside of chain request' do
      contract = RequestContract.create(item_id: item.id, inventory_id: item.inventory.first.id, quantity: item.quantity, steps: 1, user_id: User.find_by(user_name: "bob").id)
      request = ItemRequest.create(step: 1, status: :reserved, request_contract_id: contract.id, user_id: User.find_by(user_name: "bob").id, friend_id: User.find_by(user_name: "dianna").id, sent: 0, price: 100)
      item.inventory.first.update(status: :reserved)
      expect(response).to be_successful
      expect(response.body).to eq ""

      RSpec.set_user("bob")
    end
  end

  describe '#create' do
    it 'receiving invalid params and returns an errors' do
      user = User.find_by(user_name: "dianna")
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
      user = User.find_by(user_name: "dianna")
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
    describe 'update item' do
      it 'receiving invalid params and returns an errors' do
        user = User.find_by(user_name: "dianna")
        valid_params = {
          user_id: user.id, 
          quantity: 100, 
          category_id: Category.first.id, 
          name: "test", 
          grade_id: Grade.first.id, price: 100, date_available: DateTime.now, item_unit_id: ItemUnit.first.id, organic: true 
        }
        post :create, params: {item: valid_params}
        patch :update, params: {item: {
          quantity: "NaN", 
        }, id: Inventory.last.id}
        expect(response).not_to be_successful
        expect(JSON(response.body)).to eq "quantity" => ["is not a number"]
      end

      it 'receiving good params and returns an item' do
        user = User.find_by(user_name: "dianna")
        valid_params = {
          user_id: user.id, 
          quantity: 100, 
          category_id: Category.first.id, 
          name: "test", 
          grade_id: Grade.first.id, price: 100, date_available: DateTime.now, item_unit_id: ItemUnit.first.id, organic: true 
        }
        post :create, params: {item: valid_params}
        post :update, params: {item: {
          name: "not_test",
          quantity: 100,
        }, id: Inventory.last.id}
        expect(JSON(response.body)["data"]["attributes"]["name"]).to eq "not_test"
      end
      
      #params.require(:item).permit(:user_id, :quantity, :category_id, :item_name_id, :name, :grade_id, :price, :date_available, :item_unit_id, :unit, :created_at, :organic)
    end

    describe 'update gellery' do
      let!(:inventory) {create(:inventory, user: User.find_by(user_name: "bob"), status: :available, item: create(:item, user: User.find_by(user_name: "bob")))}
      it 'saves item avatars' do
        avatar = Rack::Test::UploadedFile.new(Rails.root.join('spec/support/logo-image.png'), 'image/png')
        patch :update, params: {inventory_avatars: [avatar], source_images: [avatar], id: inventory.id}
        expect(response).to be_successful
        expect(JSON(response.body)["data"]).to be_truthy
        inventory.reload
        expect(inventory.item.avatars.length).to be > 0
      end
      #params.permit({inventory_avatars: [], source_images: []})
    end

    describe 'update status' do
      let!(:inventory_origin) {create(:inventory, user: User.find_by(user_name: "bob"), status: :available, item: create(:item, user: User.find_by(user_name: "bob")))}
      let!(:inventory) {create(:inventory, user: User.find_by(user_name: "bob"), status: :reserved, ref_id: inventory_origin.id)}
      let!(:request_contract) {create(:request_contract, inventory_id: inventory.id, item: inventory.item, user: User.find_by(user_name: "bob"))}

      it 'move to available with active requests and gets an error' do
        patch :update, params: {inventory: {status: 'available'}, id: inventory.id}
        expect(response).not_to be_successful
      end

      it 'move to available with completed requests and returns the inventory' do
        request_contract.update!(status: :completed)
        patch :update, params: {inventory: {status: 'available'}, id: inventory.id}
        expect(response).to be_successful
        expect(JSON(response.body)["data"]).to be_truthy

        RSpec.set_user("dianna")
      end
      #params.require(:inventory).permit(:status)
    end
  end

  describe '#destroy' do
    let!(:inventory_origin) {create(:inventory, user: User.find_by(user_name: "dianna"), status: :available, item: create(:item, user: User.find_by(user_name: "dianna")))}
    let!(:inventory) {create(:inventory, user: User.find_by(user_name: "dianna"), status: :reserved, ref_id: inventory_origin.id, item: inventory_origin.item)}

    it 'should destroy inventory' do
      delete :destroy, params: { id: inventory_origin.id }
      expect(response).to be_successful
      expect(Inventory.find_by(id: inventory_origin.id)).to eq nil
      expect(Item.find_by(id: inventory_origin.item_id)).not_to eq nil

      RSpec.set_user("bob")
    end

    it 'should destroy inventory and item as admin' do
      delete :destroy, params: { id: inventory_origin.id }
      expect(response).to be_successful
      expect(Inventory.find_by(id: inventory_origin.id)).to eq nil
      expect(Item.find_by(id: inventory_origin.item_id)).to eq nil
    end
  end
end
