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

  validates :quantity, presence:true, numericality: true

  scope :with_contract_data, -> { joins("INNER JOIN `request_contracts` ON `request_contracts`.`inventory_id` = `inventories`.`id` INNER JOIN `item_requests` ON `item_requests`.`request_contract_id` = `request_contracts`.`id`") }

  def producer_owns?
    self.user_id == self.item.producer_id
  end

  def target_user_name(current_user)
    target_id = self.target_user_id.nil? ? self.user_id : self.target_user_id
    relation = Relationship.where "user_id IN (?) AND friend_id IN (?)",
      [current_user.id, target_id], [current_user.id, target_id]
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
        'producer' => self.item.producer_id,
        'status' => self.status,
        'action-request' => self.item_requests.where("(item_requests.friend_id = #{current_user.id} AND item_requests.status = 0) OR (item_requests.user_id = #{current_user.id} AND item_requests.status = 4)").count > 0
      }
    }
  end

  def avatars_with_item
    avatars = []
    if self.gallery_map.length > 0 && !self.gallery_map.find {|mp| mp != "<-"}
      avatars = self.item.avatars
    else
      self.gallery_map.each do |name|
        avatars.push((self.avatars && self.avatars.find {|n| n.identifier == name}) || (self.item.avatars && self.item.avatars.find {|n| n.identifier == name}) || nil)
      end
    end
    avatars.compact.map{ |i| '/v1'+i.url.gsub(Rails.root.to_s, '') }
  end

  def update_avatars (args, current_user_id)
    if current_user_id == self.item.user_id
      return self.item.update_avatars(args)
    end 

    updated_list = []
    order_map = []
    was_deleted = false #optimization flag for thumbnails cleaning up
    
    ((args[:source_images] || []).select {|arg| arg != 'null'}).each_with_index do |image, i|
      if image.is_a? String
        present_avatar = self.avatars.find {|img| img && img.url.split('/').last == image.split('/').last}
        if present_avatar
          updated_list.push(present_avatar) 
          order_map.push(image.split('/').last)
        else
          item_avatar = self.item.avatars.find {|img| img && img.url.split('/').last == image.split('/').last}
          order_map.push(image.split('/').last) if item_avatar
          was_deleted = true if !item_avatar
        end
      else
        updated_list.push(image)
        order_map.push(image.original_filename)
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
    true
  end

  def update_item_avatar_relation (old_name, new_name)
    index = self.gallery_map.index(old_name)
    if index
      self.gallery_map[index] = new_name
      self.save!
    end
  end

  def update_status (args)
    case args[:status]
    when 'available'
      self.reload
      if (self.status == 'reserved' || self.status == 'unavailable') && (!self.request_contract || self.request_contract.status == 'completed' || self.request_contract.status == 'cancelled')
        if self.request_contract
          self.request_contract.destroy
          inventory = Inventory.find_by(id: self.ref_id)
          if inventory
            inventory.update(quantity: inventory.quantity + self.quantity)
            self.destroy
          else
            self.update(status: :available)
          end
        else
          if self.ref_id
            inventory = Inventory.find_by(id: self.ref_id)
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
        return true
      else
        return false
      end
    when 'unavailable'
      self.reload
      self.status == 'available' ? self.update(status: :unavailable) : false
    else
      return false
    end
  end
end
