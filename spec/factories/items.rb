FactoryBot.define do
  factory :item do
    user { nil }
    quantity { 1 }
    unit_id { "MyString" }
    category { nil }
    item_name { nil }
    name { "MyString" }
    grade { nil }
    price { "9.99" }
    date_available { "2018-11-02 15:34:19" }
  end
end
