class Category < ApplicationRecord
  has_many :item_names, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :user_category_prices, dependent: :destroy
  has_many :user_relationship_prices, dependent: :destroy
end
