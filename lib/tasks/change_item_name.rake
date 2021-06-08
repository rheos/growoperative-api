namespace :item do
  desc 'Change item item_id'
  task :change_item_name do
    Inventory.find_by(item_id: 66, description: 'Test').delete
  end
end
