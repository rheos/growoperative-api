class Inventory < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :request_contract, primary_key: 'inventory_id', foreign_key: 'id', inverse_of: :inventory, optional: true, dependent: :destroy
  has_many :item_requests, through: :request_contract
  has_many :unit_options, dependent: :destroy
 
  mount_uploaders :avatars, ImagesUploader
  serialize :gallery_map, Array

  # Prevent S3 image deletion for demo users — images are shared across resets
  skip_callback :destroy, :before, :remove_avatars!, raise: false
  before_destroy :remove_avatars_unless_demo

  def remove_avatars_unless_demo
    return if user&.demo?
    remove_avatars!
  end

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
    else
      if self.target_user_id
        user = User.find(self.target_user_id)
        user.nickname ? user.nickname : user.user_name
      else
        self.user.user_name
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
        'category-id' => self.item.category_id, 
        'name' => self.item.name, 
        'grade-id' => self.item.grade_id,
        'item-unit-id' => self.item.item_unit_id, 
        'unit-name' => self.item.item_unit.item_symbol, 
        'item-name-id' => self.item.item_name_id, 
        'date-available' => self.item.date_available, 
        'organic' => self.item.organic, 
        'created-at' => self.created_at,
        'avatars' => avatars_with_item,
        'owner-id' => self.user_id,
        'producer' => self.item.producer_id,
        'status' => self.status,
        'action-request' => self.action_request.nil? ? self.item_requests.where("(item_requests.friend_id = #{current_user.id} AND item_requests.status = 0) OR (item_requests.user_id = #{current_user.id} AND item_requests.status = 4)").count > 0 : self.action_request != 0,
        'unit-options' => generate_options,
        'description' => self.description
      }
    }
  end

  def generate_options
    if self.unit_options.length > 0
      self.unit_options.map{|opt| opt.to_json}
    else
      (self.user.category_sizes.where(category_id: self.item.category_id) || []).map { |s| {
        id: s.id,
        quantity: s.quantity,
        price: s.price,
        unit: s.item_unit.unit_name,
        unit_data: s.item_unit,
        hidden: true
      }}
    end
  end

  def avatars_with_item
    avatars = []
    if self.gallery_map.length > 0 && !self.gallery_map.find {|mp| mp != "<-"}
      avatars = self.item.avatars
    else
      self.gallery_map.each do |name|
        # Find by identifier (filename) not by URL
        avatars.push((self.avatars && self.avatars.find {|n| n.identifier == name}) || (self.item.avatars && self.item.avatars.find {|n| n.identifier == name}) || nil)
      end
    end
    avatars.compact.map{ |i|
      if Rails.env.production? || ENV['AWS_S3_BUCKET'].present?
        i.file.public_url  # Unsigned URL — old app manipulates filenames for thumbnails
      else
        '/v1'+i.url.gsub(Rails.root.to_s, '')  # Local development URLs
      end
    }
  end

  def update_avatars (args, current_user_id)
    # Spawnling.new do
      if current_user_id == self.item.user_id
        return self.item.update_avatars(args)
      end 

      updated_list = []
      order_map = []
      was_deleted = false #optimization flag for thumbnails cleaning up
      
      ((args[:source_images] || []).select {|arg| arg != 'null'}).each_with_index do |image, i|
        if image.is_a? String
          # Extract just the filename, removing any S3 query parameters
          img_name = image.split('/').last.split('?').first.split('thumb500_').last
          present_avatar = self.avatars.find {|img| img && img.identifier == img_name}
          if present_avatar
            updated_list.push(present_avatar) 
            order_map.push(present_avatar.identifier)  # Use identifier, not URL
          else
            item_avatar = self.item.avatars.find {|img| img && img.identifier == img_name}
            if item_avatar
              order_map.push(item_avatar.identifier)  # Use identifier, not URL
            else
              was_deleted = true
            end
          end
        else
          updated_list.push(image)
          # Store just the filename, not the full path
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
        # binding.pry
        uploader.update_thumbnail(avatar)
      end
      uploader.clear_thumbnails if was_deleted
    # end
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
          self.request_contract.update(archived: true)
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
