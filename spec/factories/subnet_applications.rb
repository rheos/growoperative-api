FactoryBot.define do
  factory :subnet_application do
    sequence(:community_name) { |n| "Community #{n}" }
    location      { 'Kaslo, BC' }
    contact_name  { 'Franz Jansen' }
    sequence(:contact_email) { |n| "applicant#{n}@example.com" }
    description   { 'Already trading eggs for bread; want to formalize.' }
    status        { 'pending' }
  end
end
