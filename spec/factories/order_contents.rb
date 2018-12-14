FactoryBot.define do
  factory :order_content do
    order { nil }
    request_list { nil }
    status { "MyString" }
  end
end
