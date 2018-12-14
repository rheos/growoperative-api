FactoryBot.define do
  factory :invitation do
    invitation_code { "MyString" }
    user { nil }
    status { 1 }
    label { "MyString" }
  end
end
