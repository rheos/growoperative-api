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

# Generate category seed data
def generate_category
  Category.create!([{category_name: "herbs and greens", default_unit: 1, default_consumer_unit:2, default_node_price: 1.0},
    {category_name: "tinctures", default_unit: 3, default_consumer_unit:4, default_node_price: 1.00}])
end
generate_category

# generate Unit data
def generate_item_unit
  ItemUnit.create!(unit_name: "pounds", item_symbol: "lbs", equivalent: 453.592)
  ItemUnit.create!(unit_name: "ounces", item_symbol: "oz")
  ItemUnit.create!(unit_name: "boxes", item_symbol: "box")
  ItemUnit.create!(unit_name: "bottles", item_symbol: "bottle")
  ItemUnit.create!(unit_name: "grams", item_symbol: "g", equivalent: 1)
end
generate_item_unit


# Generate Grade
def generate_grade
  Grade.create!([{value: 10,name: "C"},{value: 20,name: "B"},{value: 30,name: "A"},{value: 40,name: "AA"},{value: 50,name: "AAA"},{value: 60,name: "A+"},{value: 70,name: "A++"},])
end
generate_grade
