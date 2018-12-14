class Item < ApplicationRecord
  belongs_to :user
  belongs_to :category
  belongs_to :item_name, optional: true
  belongs_to :grade
  belongs_to :item_unit, optional: true
  has_many   :item_requests, dependent: :destroy
  has_many   :reviews, dependent: :destroy

  attr_accessor :unit
  attr_accessor :target_user_id
  attr_accessor :total_price
  # callbacks
  before_create :set_item_name
  before_save :set_item_unit
  # This method will set item_name in item if not present
  def set_item_name
    if self.item_name_id.nil?
      item_name = ItemName.find_or_create_by(name: self.name, category_id: self.category_id)
      item_name.save
      self.item_name_id = item_name.id
    end
  end

  def set_item_unit
    if self.item_unit_id.nil?
      item_unit = ItemUnit.find_or_create_by(unit_name: self.unit)
      item_unit.save
      self.item_unit_id = item_unit.id
    end
  end
end
