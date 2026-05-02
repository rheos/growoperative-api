# Backup script to generate seeds from current database state
# Run with: rails runner db/backup_current_data.rb

puts "=== Database Backup to Seeds ==="
puts "Reading current database state..."

# Create directories
seed_images_dir = Rails.root.join('db', 'seed_images')
FileUtils.mkdir_p(seed_images_dir) unless Dir.exist?(seed_images_dir)

# Start building the seeds file content
seeds_content = []
seeds_content << "# Generated seeds file from database backup"
seeds_content << "# Created: #{Time.current}"
seeds_content << ""
seeds_content << "puts 'Loading seed data...'"
seeds_content << ""

# Helper method to format Ruby code for model creation
def format_attributes(record, excluded_attrs = [])
  attrs = record.attributes.except('id', 'created_at', 'updated_at', *excluded_attrs)
  formatted_attrs = attrs.map do |key, value|
    if value.nil?
      "#{key}: nil"
    elsif value.is_a?(String)
      "#{key}: #{value.inspect}"
    elsif value.is_a?(Time) || value.is_a?(DateTime)
      "#{key}: Time.parse(#{value.to_s.inspect})"
    elsif value.is_a?(Date)
      "#{key}: Date.parse(#{value.to_s.inspect})"
    elsif value.is_a?(Array) || value.is_a?(Hash)
      "#{key}: #{value.inspect}"
    else
      "#{key}: #{value}"
    end
  end
  formatted_attrs.join(', ')
end

# 1. Global Settings
puts "Backing up GlobalSettings..."
seeds_content << "# Global Settings"
GlobalSetting.all.each do |setting|
  seeds_content << "GlobalSetting.find_or_create_by(setting: #{setting.setting.inspect}) do |gs|"
  seeds_content << "  gs.value = #{setting.value}"
  seeds_content << "end"
end
seeds_content << ""

# 2. Categories
puts "Backing up Categories..."
seeds_content << "# Categories"
Category.all.each do |category|
  seeds_content << "cat_#{category.id} = Category.find_or_create_by(category_name: #{category.category_name.inspect}) do |c|"
  seeds_content << "  c.default_unit_id = #{category.default_unit_id.inspect}"
  seeds_content << "  c.kind = #{category.kind.inspect}"
  seeds_content << "  c.default_node_price = #{category.default_node_price}"
  seeds_content << "  c.price = #{category.price}" if category.price
  seeds_content << "end"
end
seeds_content << ""

# 3. Item Units
puts "Backing up ItemUnits..."
seeds_content << "# Item Units"
ItemUnit.all.each do |unit|
  seeds_content << "unit_#{unit.id} = ItemUnit.find_or_create_by(unit_name: #{unit.unit_name.inspect}) do |u|"
  seeds_content << "  u.item_symbol = #{unit.item_symbol.inspect}"
  seeds_content << "  u.equivalent = #{unit.equivalent}" if unit.equivalent
  seeds_content << "  u.unit_type = #{unit.unit_type.inspect}" if unit.unit_type
  seeds_content << "end"
end
seeds_content << ""

# 4. Grades
puts "Backing up Grades..."
seeds_content << "# Grades"
Grade.all.each do |grade|
  seeds_content << "grade_#{grade.id} = Grade.find_or_create_by(name: #{grade.name.inspect}) do |g|"
  seeds_content << "  g.value = #{grade.value.inspect}"
  seeds_content << "end"
end
seeds_content << ""

# 5. Users (this is complex due to invitations and relationships)
puts "Backing up Users..."
seeds_content << "# Users"
seeds_content << "users = {}"
User.all.each do |user|
  seeds_content << "users[#{user.id}] = User.find_or_create_by(user_name: #{user.user_name.inspect}) do |u|"
  seeds_content << "  u.password = 'bobsentme!'"  # Default password for seeded users
  seeds_content << "  u.invite_limit = #{user.invite_limit}"
  seeds_content << "  u.depth = #{user.depth}"
  seeds_content << "  u.invitations_count = #{user.invitations_count}"
  seeds_content << "  u.parent_id = #{user.parent_id}" if user.parent_id
  seeds_content << "  u.invited_code = #{user.invited_code.inspect}" if user.invited_code
  seeds_content << "end"
end
seeds_content << ""

# 6. User Groups
puts "Backing up UserGroups..."
seeds_content << "# User Groups"
UserGroup.all.each do |group|
  seeds_content << "UserGroup.find_or_create_by(user_id: users[#{group.user_id}].id, group_label: #{group.group_label.inspect})"
end
seeds_content << ""

# 7. Relationships
puts "Backing up Relationships..."
seeds_content << "# Relationships"
Relationship.all.each do |rel|
  seeds_content << "Relationship.find_or_create_by("
  seeds_content << "  user_id: users[#{rel.user_id}].id,"
  seeds_content << "  friend_id: users[#{rel.friend_id}].id"
  seeds_content << ") do |r|"
  seeds_content << "  r.status = #{rel.status}"
  seeds_content << "  r.action_user_id = users[#{rel.action_user_id}].id" if rel.action_user_id
  seeds_content << "  r.user_label = #{rel.user_label.inspect}" if rel.user_label
  seeds_content << "  r.friend_label = #{rel.friend_label.inspect}" if rel.friend_label
  seeds_content << "end"
end
seeds_content << ""

# 8. Item Names
puts "Backing up ItemNames..."
seeds_content << "# Item Names"
seeds_content << "item_names = {}"
ItemName.all.each do |item_name|
  seeds_content << "item_names[#{item_name.id}] = ItemName.find_or_create_by("
  seeds_content << "  name: #{item_name.name.inspect},"
  seeds_content << "  category_id: cat_#{item_name.category_id}.id"
  seeds_content << ") do |in|"
  seeds_content << "  in.description = #{item_name.description.inspect}" if item_name.description
  seeds_content << "end"
end
seeds_content << ""

# 9. Items (with images)
puts "Backing up Items..."
seeds_content << "# Items"
seeds_content << "items = {}"

Item.all.each do |item|
  # Copy item images to seed_images directory
  if item.avatars.any?
    item_seed_dir = seed_images_dir.join("item_#{item.id}")
    FileUtils.mkdir_p(item_seed_dir)
    
    item_upload_dir = Rails.root.join('private', 'uploads', 'item', 'avatars', item.id.to_s)
    if Dir.exist?(item_upload_dir)
      Dir.glob(File.join(item_upload_dir, '*')).each do |file|
        filename = File.basename(file)
        FileUtils.cp(file, item_seed_dir.join(filename))
        puts "  Copied image: #{filename}"
      end
    end
  end

  seeds_content << "items[#{item.id}] = Item.create!("
  seeds_content << "  user_id: users[#{item.user_id}].id,"
  seeds_content << "  category_id: cat_#{item.category_id}.id,"
  seeds_content << "  grade_id: grade_#{item.grade_id}.id,"
  seeds_content << "  item_name_id: item_names[#{item.item_name_id}].id,"
  seeds_content << "  item_unit_id: unit_#{item.item_unit_id}.id," if item.item_unit_id
  seeds_content << "  name: #{item.name.inspect},"
  seeds_content << "  quantity: #{item.quantity},"
  seeds_content << "  price: #{item.price},"
  seeds_content << "  organic: #{item.organic},"
  seeds_content << "  date_available: Time.parse(#{item.date_available.to_s.inspect})," if item.date_available
  seeds_content << "  producer_id: #{item.producer_id}," if item.producer_id
  seeds_content << "  avatars: #{item.avatars.inspect},"
  seeds_content << "  with_inventory: true"
  seeds_content << ")"
  seeds_content << ""
end

# 10. Copy images and create restore logic
puts "Adding image restoration logic..."
seeds_content << "# Restore Images"
seeds_content << "puts 'Copying images...'"
seeds_content << ""
seeds_content << "items.each do |original_id, item|"
seeds_content << "  seed_image_dir = Rails.root.join('db', 'seed_images', \"item_\#{original_id}\")"
seeds_content << "  if Dir.exist?(seed_image_dir)"
seeds_content << "    upload_dir = Rails.root.join('private', 'uploads', 'item', 'avatars', item.id.to_s)"
seeds_content << "    FileUtils.mkdir_p(upload_dir)"
seeds_content << "    Dir.glob(File.join(seed_image_dir, '*')).each do |file|"
seeds_content << "      filename = File.basename(file)"
seeds_content << "      FileUtils.cp(file, upload_dir.join(filename))"
seeds_content << "    end"
seeds_content << "    puts \"  Restored images for item: \#{item.name}\""
seeds_content << "  end"
seeds_content << "end"
seeds_content << ""

# 11. Inventories (if they have custom data beyond what Item creates)
puts "Backing up Inventories..."
seeds_content << "# Update Inventories with custom data"
Inventory.all.each do |inv|
  if inv.description || inv.gallery_map != ["<-", "<-", "<-", "<-", "<-"] || inv.avatars.any?
    seeds_content << "inv = items[#{inv.item_id}].inventory.first"
    seeds_content << "inv.update!("
    seeds_content << "  description: #{inv.description.inspect}," if inv.description
    seeds_content << "  gallery_map: #{inv.gallery_map.inspect}," if inv.gallery_map != ["<-", "<-", "<-", "<-", "<-"]
    seeds_content << "  avatars: #{inv.avatars.inspect}," if inv.avatars.any?
    seeds_content << "  status: #{inv.status.inspect}"
    seeds_content << ")"
  end
end
seeds_content << ""

seeds_content << "puts 'Seed data loaded successfully!'"

# Write the seeds file
seeds_file_path = Rails.root.join('db', 'seeds.rb')
File.write(seeds_file_path, seeds_content.join("\n"))

puts ""
puts "=== Backup Complete ==="
puts "Generated: db/seeds.rb"
puts "Images copied to: db/seed_images/"
puts ""
puts "To restore this data:"
puts "1. rails db:drop db:create db:migrate"
puts "2. rails db:seed"
puts ""
puts "Files ready for git commit!" 
