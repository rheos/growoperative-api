require 'rails_helper'


RSpec.describe 'Global scenario test', type: :request, skip_hooks: true do
  DatabaseCleaner.strategy = :deletion
  DatabaseCleaner.clean_with(:truncation)
  Grade.create!([{value: 10,name: "C"},{value: 20,name: "B"},{value: 30,name: "A"},{value: 40,name: "AA"},{value: 50,name: "AAA"},{value: 60,name: "A+"},{value: 70,name: "A++"},])
  ItemUnit.create!(unit_name: "pounds", item_symbol: "lbs")
  Category.create!([{category_name: "herbs and greens", default_unit: 1, default_consumer_unit:2, default_node_price: 1.0},
    {category_name: "tinctures", default_unit: 3, default_consumer_unit:4, default_node_price: 1.00}])

  $token = nil
  $invitation_code = nil

  it 'creates Admin user and global settings', skip_hooks: true do
    global_setting = GlobalSetting.find_or_initialize_by(setting: "ChainLimit")
    global_setting.save
    cat_price = GlobalSetting.find_or_initialize_by(setting: "user_category_relationship_price")
    cat_price.value = 1
    cat_price.save
    degree = GlobalSetting.find_or_initialize_by(setting: "RangeDegree")
    degree.value = 4
    degree.save

    pass_word = "bobsentme!"
    admin = User.find_or_initialize_by(user_name: "bob")
    admin.password = pass_word
    admin.invite_limit = 1000000
    admin.depth= 0
    admin.save
    admin.user_groups.create!(group_label: "admin")

    post "/login", params: {user_name: "bob", password: pass_word}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]

    get "/v1/users/generate_invitation?user_type=producer", headers: {"Authorization": $token}
    expect(JSON(response.body)["invitation_code"]).to be_truthy
    $invitation_code = JSON(response.body)["invitation_code"]
  end

  it "Dianna registration by Bob's code and invite token generation", skip_hooks: true do
    post "/signup", params: { user: {
      user_name: "dianna",
      password: "bobsentme!",
      password_confirmation: "bobsentme!",
      invited_code: $invitation_code
    }}
    
    expect(response).to be_successful
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]

    get "/v1/users/generate_invitation?user_type=broker", headers: {"Authorization": $token}
    expect(JSON(response.body)["invitation_code"]).to be_truthy
    $invitation_code = JSON(response.body)["invitation_code"]
    expect(Relationship.find_by(user_id: User.find_by(user_name: "bob").id, friend_id: User.find_by(user_name: "dianna").id)).to be_truthy
  end

  it "bruce_knows_dianna registration by Dianna's code and invite token generation", skip_hooks: true do
    post "/signup", params: { user: {
      user_name: "bruce_knows_dianna",
      password: "bobsentme!",
      password_confirmation: "bobsentme!",
      invited_code: $invitation_code
    }}
    
    expect(response).to be_successful
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]

    get "/v1/users/generate_invitation?user_type=broker", headers: {"Authorization": $token}
    expect(JSON(response.body)["invitation_code"]).to be_truthy
    $invitation_code = JSON(response.body)["invitation_code"]
    expect(Relationship.find_by(user_id: User.find_by(user_name: "dianna").id, friend_id: User.find_by(user_name: "bruce_knows_dianna").id)).to be_truthy
  end

  it "barry_knows_bruce registration by bruce_knows_dianna's code", skip_hooks: true do
    post "/signup", params: { user: {
      user_name: "barry_knows_bruce",
      password: "bobsentme!",
      password_confirmation: "bobsentme!",
      invited_code: $invitation_code
    }}
    
    expect(response).to be_successful
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]

    expect(Relationship.find_by(user_id: User.find_by(user_name: "bruce_knows_dianna").id, friend_id: User.find_by(user_name: "barry_knows_bruce").id)).to be_truthy
  end

  it "Dianna creates an item with inventory", skip_hooks: true do
    post "/login", params: {user_name: "dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "dianna")

    post "/v1/items", headers: {"Authorization": $token}, params: {
      item: {
        user_id: user.id, 
        quantity: "1000", 
        category_id: Category.first.id, 
        name: "test", 
        grade_id: Grade.first.id, 
        price: 100, 
        date_available: DateTime.now, item_unit_id: 
        ItemUnit.first.id, 
        organic: true 
      }
    }

    expect(response).to be_successful
    expect(JSON(response.body)["data"]["id"]).to eq Inventory.last.id
    user.reload
    expect(user.inventories.count).to eq 1
    expect(user.items.count).to eq 1
  end

  it "Users sets relationship prices", skip_hooks: true do
    user = User.find_by(user_name: "dianna")

    post "/v1/user_relationship_prices", headers: {"Authorization": $token}, params: {
      user_relationship_price: {
        category_id: 1,
        friend_id: User.find_by(user_name: 'bruce_knows_dianna').id,
        price: 100,
        relationship_id: user.relationships.first.id
      }
    }

    expect(response).to be_successful
    expect(user.user_relationship_prices.first.price.to_i).to eq 100

    post "/login", params: {user_name: "bruce_knows_dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "bruce_knows_dianna")

    post "/v1/user_relationship_prices", headers: {"Authorization": $token}, params: {
      user_relationship_price: {
        category_id: 1,
        friend_id: User.find_by(user_name: 'barry_knows_bruce').id,
        price: 100,
        relationship_id: user.relationships.first.id
      }
    }

    expect(response).to be_successful
    expect(user.user_relationship_prices.first.price.to_i).to eq 100
  end

  it "bruce_knows_dianna loads available and gets price without relation markup", skip_hooks: true do
    post "/login", params: {user_name: "bruce_knows_dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "bruce_knows_dianna")

    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].length).to eq 1
    expect(JSON(response.body)["data"][0]["attributes"]["total-price"].to_i).to eq 100

    inventory_id = JSON(response.body)["data"][0]["id"]
  end

  it "barry_knows_bruce loads available, gets price with relation markup and requests 25 units from Dianna's inventory through bruce_knows_dianna", skip_hooks: true do
    post "/login", params: {user_name: "barry_knows_bruce", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "barry_knows_bruce")

    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].length).to eq 1
    expect(JSON(response.body)["data"][0]["attributes"]["total-price"].to_i).to eq 200

    inventory_id = JSON(response.body)["data"][0]["id"]

    post "/v1/items/#{inventory_id}/requests", headers: {"Authorization": $token}, params: {
      request: {
        quantity: 25
      }
    }

    expect(response).to be_successful
    contract = RequestContract.find_by(user_id: user.id)
    expect(contract).to be_truthy
    expect(contract.item_requests.count).to eq 2
  end

  it "Dianna accepts request", skip_hooks: true do
    post "/login", params: {user_name: "dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "dianna")

    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful

    expect(JSON(response.body)["data"].length).to eq 1
    expect(JSON(response.body)["data"][0]["attributes"]["action-request"]).to eq 1

    request = ItemRequest.find_by(friend_id: user.id, status: :pending)
    post "/v1/items/requests/#{request.id}/accept", headers: {"Authorization": $token}

    expect(response).to be_successful
    user.reload
    expect(user.inventories.count).to eq 2
    expect(user.inventories.first.quantity.to_i).to eq 975
    expect(user.inventories.last.status).to eq "reserved"
    expect(user.inventories.last.item_requests.last.order).to be_truthy
  end

  it "Dianna reserving item for bruce_knows_dianna", skip_hooks: true do
    user = User.find_by(user_name: "dianna")

    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful

    post "/v1/items/requests/reserve", headers: {"Authorization": $token}, params: {
      inventory_id: user.inventories.first.id,
      user_id: User.find_by(user_name: 'bruce_knows_dianna').id,
      quantity: 75,
      price: 300
    }

    expect(response).to be_successful
    user.reload
    expect(user.inventories.count).to eq 3
    expect(user.inventories.last.status).to eq "reserved"
    expect(user.inventories.last.item_requests.first.status).to eq "reserved"
  end
  
  it "bruce_knows_dianna loads available and accepts requests", skip_hooks: true do
    post "/login", params: {user_name: "bruce_knows_dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "bruce_knows_dianna")

    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].length).to eq 2
    expect(JSON(response.body)["data"][1]["attributes"]["action-request"]).to eq 1
    expect(JSON(response.body)["data"][1]["attributes"]["total-price"].to_i).to eq 300

    get "/v1/items/requested", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].length).to eq 1
    expect(JSON(response.body)["data"][0][0]["attributes"]["need_sign"]).to eq true

    requests = ItemRequest.where("friend_id = #{user.id} OR (user_id = #{user.id} AND status = 4)")
    post "/v1/items/requests/#{requests[0].id}/accept", headers: {"Authorization": $token}
    expect(response).to be_successful
    post "/v1/items/requests/#{requests[1].id}/accept", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(ItemRequest.where(friend_id: user.id).select{|r| r.status != "accepted"}.length).to eq 0
    expect(ItemRequest.where(user_id: user.id).select{|r| r.status != "accepted"}.length).to eq 0
  end

  it "Dianna ships an order", skip_hooks: true do
    post "/login", params: {user_name: "dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "dianna")

    order = ItemRequest.where(friend_id: user.id).first.order
    expect(ItemRequest.where(friend_id: user.id).last.order_id).to eq order.id

    patch "/v1/orders/#{order.id}", headers: {"Authorization": $token}, params: {
      order_action: {
        action_name: "ship",
        item_id: nil
      }
    }

    expect(response).to be_successful
    expect(JSON(response.body)["data"]).to be_truthy
    expect(ItemRequest.where(friend_id: user.id).select{|r| r.status != "completed"}.length).to eq 0
  end

  it "bruce_knows_dianna signs an order, moves finished contract inventory to available and ships next contract", skip_hooks: true do
    post "/login", params: {user_name: "bruce_knows_dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "bruce_knows_dianna")

    get "/v1/items/requested", headers: {"Authorization": $token}
    expect(JSON(response.body)["data"][0]["items"].length).to eq 2
    expect(JSON(response.body)["data"][0]["items"][0]["attributes"]["need_sign"]).to eq true
    order_id = JSON(response.body)["data"][0]["order"]["id"]

    patch "/v1/orders/#{order_id}", headers: {"Authorization": $token}, params: {
      order_action: {
        action_name: "sign",
        item_id: nil
      }
    }

    expect(response).to be_successful
    expect(JSON(response.body)["data"]).to be_truthy
    expect(Order.find(order_id).order_status).to eq "signed"

    finished_inventory = RequestContract.find_by(user_id: user.id, status: :completed).inventory
    put "/v1/items/#{finished_inventory.id}", headers: {"Authorization": $token}, params: {inventory: {status: 'available'}}

    expect(response).to be_successful
    finished_inventory.reload
    expect(finished_inventory.status).to eq "available"
    expect(finished_inventory.item_requests.count).to eq 0

    pending_order = Order.find_by(order_status: :pending)
    patch "/v1/orders/#{pending_order.id}", headers: {"Authorization": $token}, params: {
      order_action: {
        action_name: "ship",
        item_id: nil
      }
    }

    expect(response).to be_successful
    pending_order.reload
    expect(pending_order.order_status).to eq "shipped"
  end

  it "barry_knows_bruce signs an order, moves finished contract inventory to available and editing avatars", skip_hooks: true do
    post "/login", params: {user_name: "barry_knows_bruce", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "barry_knows_bruce")

    get "/v1/items/requested", headers: {"Authorization": $token}
    expect(JSON(response.body)["data"][0]["items"].length).to eq 1
    expect(JSON(response.body)["data"][0]["items"][0]["attributes"]["need_sign"]).to eq true
    order_id = JSON(response.body)["data"][0]["order"]["id"]

    patch "/v1/orders/#{order_id}", headers: {"Authorization": $token}, params: {
      order_action: {
        action_name: "sign",
        item_id: nil
      }
    }

    expect(response).to be_successful
    expect(JSON(response.body)["data"]).to be_truthy
    expect(Order.find(order_id).order_status).to eq "signed"

    finished_inventory = RequestContract.find_by(user_id: user.id, status: :completed).inventory
    put "/v1/items/#{finished_inventory.id}", headers: {"Authorization": $token}, params: {inventory: {status: 'available'}}

    expect(response).to be_successful
    finished_inventory.reload
    expect(finished_inventory.status).to eq "available"
    expect(finished_inventory.item_requests.count).to eq 0

    avatar = Rack::Test::UploadedFile.new(Rails.root.join('spec/support/logo-image.png'), 'image/png')
    patch "/v1/items/#{finished_inventory.id}", params: {inventory_avatars: [avatar], source_images: [avatar], id: finished_inventory.id}

    expect(response).to be_successful
    expect(JSON(response.body)["data"]).to be_truthy
    finished_inventory.reload
    expect(finished_inventory.item.avatars.length).to eq 0
    expect(finished_inventory.avatars.length).to eq 1
  end

  it "Dianna owns an inventory without item produced by self, and markups are applied to chain", skip_hooks: true do
    post "/login", params: {user_name: "dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "dianna")

    post "/v1/items", headers: {"Authorization": $token}, params: {
      item: {
        user_id: user.id, 
        quantity: "1000", 
        category_id: Category.first.id, 
        name: "no_owner", 
        grade_id: Grade.first.id, 
        price: 100, 
        date_available: DateTime.now, item_unit_id: 
        ItemUnit.first.id, 
        organic: true 
      }, dtype: 1
    }

    expect(response).to be_successful
    expect(Item.find_by(name: "no_owner").producer_id).to eq nil

    post "/login", params: {user_name: "bruce_knows_dianna", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "bruce_knows_dianna")

    # should apply 100 markup to item's price
    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].find{|item| item["id"] == 5}["attributes"]["total-price"].to_i).to eq 200


    post "/login", params: {user_name: "barry_knows_bruce", password: "bobsentme!"}
    expect(response.headers["authorization"]).to be_truthy
    $token = response.headers["authorization"]
    user = User.find_by(user_name: "barry_knows_bruce")

    # should apply 100 + 100 markup to item's price
    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].find{|item| item["id"] == 5}["attributes"]["total-price"].to_i).to eq 300
   
  end

  it "Markups are deleted, and default markup is used", skip_hooks: true do
    UserRelationshipPrice.destroy_all
    # should apply 1 + 1 default node prices
    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].find{|item| item["id"] == 5}["attributes"]["total-price"].to_i).to eq 102

    # create item category price and default node price
    UserCategoryPrice.create(user_id: User.find_by(user_name: 'dianna').id, category_id: Category.first.id, unit: ItemUnit.first.unit_name, price: 10)
    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    expect(JSON(response.body)["data"].find{|item| item["id"] == 5}["attributes"]["total-price"].to_i).to eq 111

    Category.first.update(default_node_price: 20)
    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    # should be 10 + 20 (category price for 1 relation and default category node price for 2 relation)
    expect(JSON(response.body)["data"].find{|item| item["id"] == 5}["attributes"]["total-price"].to_i).to eq 130

    UserCategoryPrice.destroy_all
    get "/v1/items?range_degree=2", headers: {"Authorization": $token}
    expect(response).to be_successful
    # should be 20 + 20 (default category node prices only)
    expect(JSON(response.body)["data"].find{|item| item["id"] == 5}["attributes"]["total-price"].to_i).to eq 140
  end
end