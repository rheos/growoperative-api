class Inventory < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :request_contract, primary_key: 'inventory_id', foreign_key: 'id', inverse_of: :inventory, optional: true, dependent: :destroy
  has_many :item_requests, through: :request_contract
 
  mount_uploaders :avatars, ImagesUploader

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
        'avatars' => (self.avatars || self.item.avatars || []).map { |i| '/v1'+i.url.gsub(Rails.root.to_s, '') },
        'owner-id' => self.user_id,
      }
    }
  end

  def update_avatars (args)
    updated_list = []
    was_deleted = false #optimization flag for thumbnails cleaning up
  
    (args[:source_images] || []).each_with_index do |image, i|
      if image.is_a? String
        present_avatar = self.avatars.find {|img| img.url.split('/').last == image.split('/').last}
        updated_list[i] = present_avatar
        was_deleted = true if present_avatar 
      else
        updated_list[i] = image
      end
    end
    self.avatars = updated_list.compact
    self.save

    # update thumbnails
    if self.avatars.length > 0
      uploader = self.avatars[0]
      (args[:inventory_avatars].compact || []).each do |avatar|
        uploader.update_thumbnail(avatar, self.avatars.map {|img| img.url.split('/').last})
      end
    end

    uploader.clear_thumbnails if was_deleted
  end

  def update_status (args)
    case args[:status]
    when 'available'
      if self.status == 'reserved' && self.request_contract.status == 'completed'
        self.update(status: :available)
        self.request_contract.destroy
      else
        false
      end
    else
      false
    end
  end
end
