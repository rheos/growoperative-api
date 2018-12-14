FactoryBot.define do
  factory :user_relationship_request_price do
    user { nil }
    friend_id { 1 }
    relationship { nil }
    request_list { nil }
    price { "9.99" }
  end
end
