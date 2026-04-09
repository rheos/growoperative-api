class UserGroup < ApplicationRecord
  belongs_to :user
  # group label is enum type
  enum group_label: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin, :demo, :superuser]
end
