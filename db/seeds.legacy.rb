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

def generate_global_setting
  global_setting = GlobalSetting.find_or_initialize_by(setting: "ChainLimit")
  global_setting.save
  degree = GlobalSetting.find_or_initialize_by(setting: "RangeDegree")
  degree.value = 4
  degree.save
  demo_setup = GlobalSetting.find_or_initialize_by(setting: "demo_setup_enabled")
  demo_setup.value = 1
  demo_setup.save
end
# This will generate seed for global setting
generate_global_setting



def generate_sample_data
  pass_word = "bobsentme!"
  admin = User.find_or_initialize_by(user_name: "bob")
  admin.password = pass_word
  admin.invite_limit = 1000000
  admin.depth= 0
  admin.save
  admin.user_groups.create!(group_label: "admin")
  # Diana 
  daina_inv = admin.invitations.create!(user_type: "producer")
  daina = User.create!(user_name: "dianna", invited_code: daina_inv.invitation_code, password: pass_word )
  # Peter relationship
  peter_inv = admin.invitations.create!(user_type: "broker")
  peter = User.create!(user_name: "peter", invited_code: peter_inv.invitation_code, password: pass_word )
  # Paul relationship
  paul_inv = peter.invitations.create!(user_type: "broker")
  paul = User.create!(user_name: "paul", invited_code: paul_inv.invitation_code, password: pass_word )
  # Sara relationship
  sara_inv = peter.invitations.create!(user_type: "producer")
  sara = User.create!(user_name: "sara", invited_code: sara_inv.invitation_code, password: pass_word )
  # Mary relationship
  mary_inv = peter.invitations.create!(user_type: "broker")
  mary = User.create!(user_name: "mary", invited_code: mary_inv.invitation_code, password: pass_word )
  # Peter & mary relationship
  # p_mary_inv = peter.invitations.create!(user_type: "broker")
  # relationship = Relationship.create!(user_id: p_mary_inv.user_id, friend_id: mary.id, status: 1, action_user_id: mary.id)
  # UserGroup.create!(user_id: mary.id, group_label: "broker")
  # Bruce 
  bruce_inv = admin.invitations.create!(user_type: "broker")
  bruce = User.create!(user_name: "bruce", invited_code: bruce_inv.invitation_code, password: pass_word )

  # Arthur 
  arthur_inv = bruce.invitations.create!(user_type: "retailer")
  arthur = User.create!(user_name: "arthur", invited_code: arthur_inv.invitation_code, password: pass_word )

  # Mark 
  mark_inv = arthur.invitations.create!(user_type: "consumer")
  mark = User.create!(user_name: "mark", invited_code: mark_inv.invitation_code, password: pass_word )

  # Clark 
  clark_inv = admin.invitations.create!(user_type: "broker")
  clark = User.create!(user_name: "clark", invited_code: clark_inv.invitation_code, password: pass_word )

  # Oliver 
  oliver_inv = clark.invitations.create!(user_type: "retailer")
  oliver = User.create!(user_name: "oliver", invited_code: oliver_inv.invitation_code, password: pass_word )

  # Barry 
  barry_inv = bruce.invitations.create!(user_type: "broker")
  barry = User.create!(user_name: "barry", invited_code: barry_inv.invitation_code, password: pass_word )
  # Oliver & Barry relationship
  o_barry_inv = oliver.invitations.create!(user_type: "retailer")
  relationship = Relationship.create!(user_id: o_barry_inv.user_id, friend_id: barry.id, status: 1, action_user_id: barry.id)
  UserGroup.create!(user_id: barry.id, group_label: "retailer")
  # John 
  john_inv = barry.invitations.create!(user_type: "producer")
  john = User.create!(user_name: "john", invited_code: john_inv.invitation_code, password: pass_word )
end

# Test data
generate_sample_data

# Mark all seed users as demo
def mark_demo_users
  %w[bob dianna peter paul sara mary bruce arthur clark oliver barry mark john].each do |name|
    user = User.find_by(user_name: name)
    user&.user_groups&.find_or_create_by!(group_label: 'demo')
  end
end
mark_demo_users

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
