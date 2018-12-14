FactoryBot.define do
  factory :request_list do
    user { nil }
    item { nil }
    quantity { 1 }
    units { "MyString" }
    price { "9.99" }
    staus { 1 }
  end
end
