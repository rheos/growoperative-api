class Item < ApplicationRecord
  belongs_to :user
  belongs_to :category
  belongs_to :item_name, optional: true
  belongs_to :grade
  belongs_to :item_unit, optional: true
  has_many   :reviews, dependent: :destroy
  has_many   :inventory, dependent: :destroy

  mount_uploaders :avatars, ImagesUploader

  validates :quantity, presence:true, numericality: true

  attr_accessor :unit
  
  # callbacks
  before_create :set_item_name
  before_save :set_item_unit
  after_create :add_inventory
  # This method will set item_name in item if not present
  def set_item_name
    if self.item_name_id.nil?
      item_name = ItemName.find_or_create_by(name: self.name, category_id: self.category_id)
      item_name.save
      self.item_name_id = item_name.id
    end
  end

  def set_item_unit
    if self.item_unit_id.nil?
      item_unit = ItemUnit.find_or_create_by(unit_name: self.unit)
      item_unit.save
      self.item_unit_id = item_unit.id
    end
  end

  def add_inventory
    inventory = self.inventory.new do |m|
      m.user_id = self.user_id 
      m.quantity = self.quantity
      m.price = self.price
      m.status = :available
      m.gallery_map = ['<-', '<-', '<-', '<-', '<-']
      m.save
    end
  end

  def update_avatars (args)

    updated_list = []
    was_deleted = false #optimization flag for thumbnails cleaning up
  
    (args[:source_images] || []).each_with_index do |image, i|
      if image.is_a? String
        present_avatar = self.avatars.find {|img| img.url.split('/').last == image.split('/').last}
        updated_list[i] = present_avatar
        was_deleted = true if !present_avatar 
      else
        updated_list[i] = image
      end
    end
    self.avatars = updated_list.compact
    self.save

    # update thumbnails
    uploader = ImagesUploader.new(self, 'avatars')
    (args[:inventory_avatars].compact || []).each do |avatar|
      uploader.update_thumbnail(avatar, self.avatars.map {|img| img.url && img.url.split('/').last})
    end
    uploader.clear_thumbnails if was_deleted
    true
  end
end
