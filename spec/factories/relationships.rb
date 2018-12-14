FactoryBot.define do
  factory :relationship do
    invited_id { 1 }
    status { 1 }
    action_user_id { 1 }
    user { nil }
  end
end
