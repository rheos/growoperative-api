FactoryBot.define do
  factory :item do    
    quantity { 1 }
    name { "MyString" }
    price { "9.99" }
    date_available { "2018-11-02 15:34:19" }
    organic { true }
    avatars { [] }
    association :user, factory: :user
    association :category, factory: :category
    association :grade, factory: :grade
  end
end
