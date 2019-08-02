FactoryBot.define do
  factory :inventory do
    price { 100 }
    quantity { 100 }
    avatars { [] }
    status { 1 }
    ref_id { nil }
    association :user, factory: :user
    association :item, factory: :item
  end
end
