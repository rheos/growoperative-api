#Table structure
#   bigint  => user_id
#   bigint  => category_id
#   decimal => price
#   string  => unit
#---------------------------
class UserCategoryPrice < ApplicationRecord
  belongs_to :user
  belongs_to :category

  after_create :check_unit


  def check_unit
    item_unit = ItemUnit.find_by(unit_name: self.unit)
    unless item_unit
      ItemUnit.create(unit_name: self.unit)
    end
  end
end
