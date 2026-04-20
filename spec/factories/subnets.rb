FactoryBot.define do
  factory :subnet do
    sequence(:name) { |n| "Subnet #{n}" }
    seed_user { User.create!(user_name: "seed_#{SecureRandom.hex(4)}", password: 'bobsentme!') }
  end

  factory :subnet_membership do
    user { User.create!(user_name: "sm_#{SecureRandom.hex(4)}", password: 'bobsentme!') }
    association :subnet, factory: :subnet
    is_primary { false }
  end

  factory :subnet_config do
    association :subnet, factory: :subnet
    version { 1 }
    config { {} }
  end
end
