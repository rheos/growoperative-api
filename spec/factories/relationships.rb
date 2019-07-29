FactoryBot.define do
  factory :relationship do
    status { 1 }
    action_user_id { 1 }
    user { nil }
  end
end
