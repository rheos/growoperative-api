FactoryBot.define do
  factory :order do
    relationship { nil }
    total { "9.99" }
    status { "MyString" }
    paid { 1 }
  end
end
