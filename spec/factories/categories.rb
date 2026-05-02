FactoryBot.define do
  factory :category do
    category_name { "MyString" }
    association :default_unit, factory: :item_unit
    kind { :produce }
    default_node_price { "9.99" }
  end
end
