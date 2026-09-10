# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or create!d alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create!([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create!(name: 'Luke', movie: movies.first)

# def generate_admin_user
#   admin = User.find_or_initialize_by(user_name: "admin")
#   admin.password = "TestTest"
#   admin.invite_limit = 1000000
#   admin.depth= 0
#   admin.save
#   admin.user_groups.create!(group_label: "admin")
# end
# It will generate Admin user
# generate_admin_user

# Global settings required for the app to function
def generate_global_setting
  global_setting = GlobalSetting.find_or_initialize_by(setting: "ChainLimit")
  global_setting.save
  degree = GlobalSetting.find_or_initialize_by(setting: "RangeDegree")
  degree.value = 4
  degree.save
  GlobalSetting.find_or_create_by!(setting: "MinimumIosBuildNumber") { |s| s.value = 0 }
  GlobalSetting.find_or_create_by!(setting: "MinimumAndroidVersionCode") { |s| s.value = 0 }
  GlobalSetting.find_or_create_by!(setting: "RequiredUpdateMessage") do |s|
    s.value = 0
    s.string_value = "This version of GrowOperative is no longer compatible. Please update to continue."
  end
end
generate_global_setting

# Bootstrap admin user
def generate_admin_user
  admin = User.find_or_initialize_by(user_name: "robin")
  admin.password = "password"
  admin.invite_limit = 1000000
  admin.depth = 0
  admin.save!
  %w[superuser admin broker].each do |role|
    admin.user_groups.find_or_create_by!(group_label: role)
  end
end
generate_admin_user

# generate Unit data
def generate_item_unit
  [
    { unit_name: "grams", item_symbol: "g", unit_type: :weight, equivalent: 1 },
    { unit_name: "kilograms", item_symbol: "kg", unit_type: :weight, equivalent: 1000 },
    { unit_name: "ounces", item_symbol: "oz", unit_type: :weight, equivalent: 28.3495 },
    { unit_name: "pounds", item_symbol: "lb", unit_type: :weight, equivalent: 453.592 },
    { unit_name: "each", item_symbol: "each", unit_type: :discrete, equivalent: nil },
    { unit_name: "dozen", item_symbol: "dozen", unit_type: :discrete, equivalent: nil },
    { unit_name: "half-dozen", item_symbol: "half-dozen", unit_type: :discrete, equivalent: nil },
    { unit_name: "6-pack", item_symbol: "6-pack", unit_type: :discrete, equivalent: nil },
    { unit_name: "bunch", item_symbol: "bunch", unit_type: :discrete, equivalent: nil },
    { unit_name: "head", item_symbol: "head", unit_type: :discrete, equivalent: nil },
    { unit_name: "jar", item_symbol: "jar", unit_type: :discrete, equivalent: nil },
    { unit_name: "bottle", item_symbol: "bottle", unit_type: :discrete, equivalent: nil },
    { unit_name: "case", item_symbol: "case", unit_type: :discrete, equivalent: nil },
    { unit_name: "packet", item_symbol: "packet", unit_type: :discrete, equivalent: nil }
  ].each do |attrs|
    unit = ItemUnit.find_or_initialize_by(item_symbol: attrs[:item_symbol])
    unit.update!(attrs)
  end
end
generate_item_unit

# Generate category seed data
def generate_category
  {
    "herbs and greens" => "Herbs and Greens",
    "tinctures" => "Tinctures"
  }.each do |old_name, new_name|
    category = Category.find_by(category_name: old_name)
    category.update!(category_name: new_name) if category && category.category_name != new_name
  end

  category_configs = [
    { name: "Vegetables", default: "lb", units: %w[lb oz kg g each bunch], kind: :produce, price: 1.0 },
    { name: "Fruit", default: "lb", units: %w[lb oz kg g each], kind: :produce, price: 1.0 },
    { name: "Herbs and Greens", default: "bunch", units: %w[bunch head lb oz g each], kind: :produce, price: 1.0 },
    { name: "Herbs", default: "bunch", units: %w[bunch oz g each], kind: :produce, price: 1.0 },
    { name: "Eggs", default: "dozen", units: %w[dozen half-dozen each], kind: :produce, price: 1.0 },
    { name: "Meat", default: "lb", units: %w[lb], kind: :produce, price: 1.0 },
    { name: "Plant Starts", default: "each", units: %w[each 6-pack], kind: :produce, price: 1.0 },
    { name: "Honey & Preserves", default: "jar", units: %w[jar oz lb], kind: :produce, price: 1.0 },
    { name: "Hot Sauce / Bottled", default: "bottle", units: %w[bottle], kind: :produce, price: 1.0 },
    { name: "Tinctures", default: "bottle", units: %w[bottle oz g], kind: :produce, price: 1.0 },
    { name: "Garden Equipment", default: "each", units: %w[each dozen], kind: :goods, price: 1.0 },
    { name: "Tools", default: "each", units: %w[each dozen], kind: :goods, price: 1.0 },
    { name: "Containers & Packaging", default: "each", units: %w[each dozen case], kind: :goods, price: 1.0 },
    { name: "Seeds & Inputs", default: "packet", units: %w[packet oz g lb], kind: :goods, price: 1.0 },
    { name: "Books & Media", default: "each", units: %w[each dozen], kind: :goods, price: 1.0 },
    { name: "Other / Miscellaneous", default: "each", units: %w[each lb dozen], kind: :goods, price: 1.0 }
  ]

  category_configs.each do |config|
    default_unit = ItemUnit.find_by!(item_symbol: config[:default])
    category = Category.find_or_initialize_by(category_name: config[:name])
    category.default_unit = default_unit
    category.default_node_price = config[:price]
    category.kind = config[:kind]
    category.save!

    config[:units].each_with_index do |symbol, index|
      unit = ItemUnit.find_by!(item_symbol: symbol)
      category_unit = category.category_units.find_or_initialize_by(item_unit: unit)
      category_unit.display_order = index
      category_unit.save!
    end
  end
end
generate_category

# Generate Grade
def generate_grade
  [{value: 10,name: "C"},{value: 20,name: "B"},{value: 30,name: "A"},{value: 40,name: "AA"},{value: 50,name: "AAA"},{value: 60,name: "A+"},{value: 70,name: "A++"}].each do |attrs|
    Grade.find_or_create_by!(attrs)
  end
end
generate_grade
