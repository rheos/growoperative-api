class Item < ApplicationRecord
  belongs_to :user
  belongs_to :category
  belongs_to :item_name, optional: true
  belongs_to :grade, optional: true
  belongs_to :item_unit, optional: true
  belongs_to :pack_contains_unit, class_name: 'ItemUnit', optional: true
  has_many   :reviews, dependent: :destroy
  has_many   :inventory, dependent: :destroy

  mount_uploaders :avatars, ImagesUploader

  # Prevent S3 image deletion for demo users — images are shared across resets
  skip_callback :destroy, :before, :remove_avatars!, raise: false
  before_destroy :remove_avatars_unless_demo

  def remove_avatars_unless_demo
    return if user&.demo?
    remove_avatars!
  end

  validates :quantity, presence:true, numericality: true

  attr_accessor :unit, :with_inventory

  enum condition: {
    condition_new: 0,
    condition_used: 1,
    condition_n_a: 2
  }
  
  # Variable-weight "buy a share" listings (meat): priced per pound of
  # carcass/hanging weight. per_unit (default) leaves existing listings alone.
  enum pricing_basis: {
    per_unit: 0,
    per_weight: 1
  }

  with_options if: :per_weight? do
    validates :est_weight_min, :est_weight_max, presence: true,
              numericality: { greater_than: 0 }
    validates :cut_yield_factor,
              numericality: { greater_than: 0, less_than_or_equal_to: 1 }
    validates :on_the_rail_delta, numericality: { greater_than_or_equal_to: 0 }
    validate :est_weight_range_ordered
  end

  # Effective per-lb rate billed (on-the-rail knocks off the delta).
  def billed_rate(on_the_rail: false)
    VariableWeightEstimate.billed_rate(
      price, on_the_rail_delta, on_the_rail: on_the_rail && on_the_rail_available
    )
  end

  # [low, high] billed estimate across the carcass-weight range.
  def billed_estimate_range(on_the_rail: false)
    VariableWeightEstimate.billed_range(
      billed_rate(on_the_rail: on_the_rail), est_weight_min, est_weight_max
    )
  end

  # [low, high] take-home (packaged cut) weight across the range.
  def take_home_estimate_range
    VariableWeightEstimate.take_home_range(est_weight_min, est_weight_max, cut_yield_factor)
  end

  # Effective $/lb of packaged meat (billed rate / yield).
  def packaged_rate(on_the_rail: false)
    VariableWeightEstimate.packaged_rate(billed_rate(on_the_rail: on_the_rail), cut_yield_factor)
  end

  def est_weight_range_ordered
    return if est_weight_min.blank? || est_weight_max.blank?
    return unless est_weight_min > est_weight_max
    errors.add(:est_weight_max, 'must be at least the minimum weight')
  end

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
    return unless self.unit
    i_unit = ItemUnit.find_or_create_by(unit_name: self.unit)
    i_unit.save
    if self.item_unit_id != i_unit.id
      self.item_unit_id = i_unit.id
    end
  end

  def add_inventory
    return if with_inventory
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
    # Always store just the filename, not the full URL
    self.avatars.map {|img| 
      if Rails.env.production?
        # For S3, extract just the filename from the URL
        img.identifier  # This gives us just the filename
      else
        # For local files, extract filename from path
        img.url.split('/').last
      end
    }
  end
end
