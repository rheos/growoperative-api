class Category < ApplicationRecord
  PICKER_ORDER = [
    'Vegetables',
    'Fruit',
    'Herbs and Greens',
    'Herbs',
    'Greens',
    'Eggs',
    'Meat',
    'Plant Starts',
    'Honey & Preserves',
    'Hot Sauce / Bottled',
    'Tinctures',
    'Garden Equipment',
    'Tools',
    'Containers & Packaging',
    'Seeds & Inputs',
    'Books & Media',
    'Other / Miscellaneous'
  ].freeze

  belongs_to :default_unit, class_name: 'ItemUnit', optional: true
  has_many :item_names, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :user_category_prices, dependent: :destroy
  has_many :user_relationship_prices, dependent: :destroy
  has_many :category_units, -> { order(:display_order) }, dependent: :destroy
  has_many :allowed_units, through: :category_units, source: :item_unit

  enum :kind, {
    produce: 0,
    goods: 1
  }

  scope :visible_to, ->(_user) { all }

  def self.for_picker
    all.sort_by { |category| [picker_order_for(category.category_name), category.category_name.to_s] }
  end

  def self.picker_order_for(category_name)
    normalized_order = PICKER_ORDER.map(&:downcase)
    normalized_order.index(category_name.to_s.downcase).presence || PICKER_ORDER.length
  end
end
