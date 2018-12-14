FactoryBot.define do
  factory :user_category_price do
    user { nil }
    category { nil }
    price { "9.99" }
    unit { "MyString" }
  end
end
