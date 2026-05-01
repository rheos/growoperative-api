#Table structure
#   bigint  => user_id
#   bigint  => category_id
#   decimal => price
#   string  => price_type
#   string  => unit
#---------------------------
class UserCategoryPrice < ApplicationRecord
  MARKUP_TYPES = %w[flat percent].freeze

  belongs_to :user
  belongs_to :category

  after_create :check_unit
  validates :price_type, inclusion: { in: MARKUP_TYPES }


  def check_unit
    item_unit = ItemUnit.find_by(unit_name: self.unit)
    unless item_unit
      ItemUnit.create(unit_name: self.unit)
    end
  end
end
