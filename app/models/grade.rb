class Grade < ApplicationRecord
  has_many :items, dependent: :destroy
end
