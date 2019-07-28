class Inventory < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :request_contract, primary_key: 'inventory_id', foreign_key: 'id', inverse_of: :inventory, optional: true, dependent: :destroy
  has_many :item_requests, through: :request_contract
 
  mount_uploaders :avatars, ImagesUploader
  serialize :gallery_map, Array

  enum status: [ :unavailable, :available, :reserved, :in_order ]

  attr_accessor :target_user_id
  attr_accessor :total_price
  attr_accessor :action_request

  scope :with_contract_data, -> { joins("INNER JOIN `request_contracts` ON `request_contracts`.`inventory_id` = `inventories`.`id` INNER JOIN `item_requests` ON `item_requests`.`request_contract_id` = `request_contracts`.`id`") }

  def producer_owns?
    self.user_id == self.item.producer_id
  end

  def target_user_name(current_user)
    relation = Relationship.where "user_id IN (?) AND friend_id IN (?)",
      [current_user.id, self.target_user_id], [current_user.id, self.target_user_id]
    if relation.first
      if (relation.first.user_id == current_user.id) && relation.first.friend_label.present?
        relation.first.friend_label
      elsif (relation.first.friend_id == current_user.id) && relation.first.user_label.present?
        relation.first.user_label
      elsif self.target_user_id
        user = User.find(self.target_user_id)
        user.nickname ? user.nickname : user.user_name
      end
    end
  end 

  def to_json(current_user)
    {
      :id => self.id, 
      :attributes => {
        'quantity' => self.quantity, 
        'total-price' => self.total_price.nil? ? self.price: self.total_price, 
        'user-id' => self.target_user_id.nil? ? self.user_id : self.target_user_id,
        'target-user-id' => self.target_user_id.nil? ? self.user_id : self.target_user_id, 
        'target-user-name' => self.target_user_name(current_user),
        'action-request' => self.action_request,
        'category-id' => self.item.category_id, 
        'name' => self.item.name, 
        'grade-id' => self.item.grade_id,
        'item-unit-id' => self.item.item_unit_id, 
        'unit-name' => self.item.item_unit.unit_name, 
        'item-name-id' => self.item.item_name_id, 
        'date-available' => self.item.date_available, 
        'organic' => self.item.organic, 
        'created-at' => self.created_at,
        'avatars' => avatars_with_item,
        'owner-id' => self.user_id,
      }
    }
  end

  def avatars_with_item
    avatars = []
    self.gallery_map.each_with_index do |s, i|
      if s == '+'
        avatars.push(self['avatars'] && self['avatars'][i] && self.avatars.find {|n| n.identifier == self['avatars'][i]})
      elsif s == '<-'
        avatars.push(self.item['avatars'] && self.item['avatars'][i] && self.item.avatars.find {|n| n.identifier == self.item['avatars'][i]})
      end
    end
    avatars.compact.map{ |i| '/v1'+i.url.gsub(Rails.root.to_s, '') }
  end

  def update_avatars (args, current_user_id)
    if current_user_id == self.item.user_id
      self.item.update_avatars(args)
      return
    end 

    updated_list = []
    order_map = []
    was_deleted = false #optimization flag for thumbnails cleaning up
    
    ((args[:source_images] || []).select {|arg| arg != 'null'}).each_with_index do |image, i|
      if image.is_a? String
        present_avatar = self.avatars.find {|img| img && img.url.split('/').last == image.split('/').last}
        updated_list[i] = present_avatar
        if present_avatar
          order_map[i] = '+'
        else
          order_map[i] = (self.item.avatars.find {|img| img && img.url.split('/').last == image.split('/').last}) ? '<-' : '-'
        end
      else
        updated_list[i] = image
        order_map[i] = '+'
      end
    end

    self.avatars = updated_list
    self.gallery_map = order_map
    self.save!

    # update thumbnails
    uploader = ImagesUploader.new(self, 'avatars')
    avatar_names = self.avatars.map {|img| img.url && img.url.split('/').last}
    (args[:inventory_avatars].compact || []).each do |avatar|
      uploader.update_thumbnail(avatar, avatar_names.compact)
    end
    uploader.clear_thumbnails if was_deleted
  end

  def update_status (args)
    case args[:status]
    when 'available'
      if self.status == 'reserved' && (!self.request_contract || self.request_contract.status == 'completed' || self.request_contract.status == 'cancelled')
        if self.request_contract
          self.update(status: :available)
          self.request_contract.destroy
        else
          if self.ref_id
            inventory = Inventory.find(self.ref_id)
            if inventory
              inventory.update(quantity: inventory.quantity + self.quantity)
              self.destroy
            else
              self.update(status: :available)
            end
          else
            self.update(status: :available)
          end
        end
      else
        false
      end
    else
      false
    end
  end
end
