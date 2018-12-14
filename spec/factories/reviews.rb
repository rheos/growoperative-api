FactoryBot.define do
  factory :review do
    user { nil }
    item_name { nil }
    item { nil }
    producer_id { 1 }
    value { 1 }
  end
end
