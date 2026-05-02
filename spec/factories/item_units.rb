FactoryBot.define do
  factory :item_unit do
    unit_name { "pounds" }
    item_symbol { "lb" }
    unit_type { :weight }
    equivalent { 453.592 }
  end
end
