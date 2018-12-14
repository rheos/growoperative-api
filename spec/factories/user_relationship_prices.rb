FactoryBot.define do
  factory :user_relationship_price do
    user { nil }
    friend { nil }
    category { nil }
    relation { nil }
    price { "9.99" }
    receiving_price { "" }
    receiving_price_type { "MyString" }
  end
end
