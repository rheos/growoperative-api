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
    i_unit = ItemUnit.find_or_create_by(unit_name: self.unit)
    i_unit.save
    if self.item_unit_id != i_unit.id
      self.item_unit_id = i_unit.id
    end
  end

  def add_inventory
    inventory = self.inventory.new do |m|
      m.user_id = self.user_id 
      m.quantity = self.quantity
      m.price = self.price
      m.status = :available
      m.gallery_map = ["<-", "<-", "<-", "<-", "<-"]
      m.save
    end
  end

  def update_avatars (args)
    origin_list = self['avatars']
    updated_list = []
    was_deleted = false #optimization flag for thumbnails cleaning up

    (args[:source_images] || []).each_with_index do |image, i|
      if image.is_a? String
        img_name = image.split('/').last.split('thumb500_').last
        present_avatar = self.avatars.find {|img| img.url.split('/').last == img_name}
        updated_list[i] = present_avatar
        was_deleted = true if !present_avatar 
      else
        updated_list[i] = image
      end
    end
    self.avatars = updated_list.compact
    self.save!

    self.inventory.each do |i|
      # add images links to gallery, if it wasn't overrided yet
      if i.gallery_map.find("<-")
        i.update(gallery_map: self.get_avatars_for_inventory + ["<-"])
      # or remove image link from inventory, if it was pointed and deleted then
      else
        gallery = i.gallery_map
        origin_list.each_with_index do |val, index|
          if gallery.find(val) && !updated_list.find{|img| img.url.split('/').last}
            gallery.delete(val)
          end
        end
        i.update(gallery_map: gallery)
      end
    end

    # update thumbnails
    uploader = ImagesUploader.new(self, 'avatars')
    (args[:inventory_avatars].compact || []).each do |avatar|
      uploader.update_thumbnail(avatar)
    end
    uploader.clear_thumbnails if was_deleted
    true
  end

  def get_avatars_for_inventory
    self.avatars.map {|img| img.url.split('/').last}
  end
end
