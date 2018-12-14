class ItemUnit < ApplicationRecord
  has_many :items, dependent: :destroy
end
