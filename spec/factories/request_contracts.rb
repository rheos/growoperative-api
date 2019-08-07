FactoryBot.define do
  factory :request_contract do
    association :user, factory: :user
    association :item, factory: :item
    inventory_id { 1 }
    quantity {100}
    status { 0 }
    steps { 1 }
    current_step { 1 }
  end
end
