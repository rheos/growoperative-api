FactoryBot.define do
  factory :notification do
    association :recipient, factory: :user
    association :actor,     factory: :user
    notification_type { 'request_created' }
    message { 'alice requested tomatoes' }
    actor_name { 'alice' }
    target_type { 'item' }
    target_id { 1 }
    target_screen { 'item_detail' }
    read { false }
  end
end
