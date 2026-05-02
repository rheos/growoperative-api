class ItemUnit < ApplicationRecord
  has_many :items, dependent: :destroy
  has_many :category_sizes, dependent: :destroy
  has_many :category_units, dependent: :destroy
  has_many :categories, through: :category_units

  enum unit_type: {
    weight: 0,
    count: 1,
    volume: 2,
    discrete: 3
  }, _prefix: :unit_type
end
