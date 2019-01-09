FactoryBot.define do
  factory :user do
    email { "admin@test.com" }
    password { 'admin123456' }
    user_name { 'admin' }
  end
end
