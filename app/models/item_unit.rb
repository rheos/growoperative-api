class ItemUnit < ApplicationRecord
  has_many :items, dependent: :destroy
  has_many :category_sizes, dependent: :destroy
end
