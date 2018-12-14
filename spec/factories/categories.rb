FactoryBot.define do
  factory :category do
    category_name { "MyString" }
    default_unit { 1 }
    default_consumer_unit { 1 }
    default_node_price { "9.99" }
  end
end
