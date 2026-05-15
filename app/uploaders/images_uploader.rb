require 'carrierwave/processing/rmagick'

class ImagesUploader < CarrierWave::Uploader::Base
  # Include RMagick or MiniMagick support:
  include CarrierWave::RMagick

  # Choose what kind of storage to use for this uploader:
  if Rails.env.production? || ENV['AWS_S3_BUCKET'].present?
    storage :fog
  else
    storage :file
  end

  # Override the directory where uploaded files will be stored.
  # This is a sensible default for uploaders that are meant to be mounted:
  def store_dir
    if Rails.env.production? || ENV['AWS_S3_BUCKET'].present?
      "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
    else
      "../private/uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
    end
  end


  # Only allow image file types
  def content_type_allowlist
    /image\//
  end

  # Reject files larger than 10MB
  def size_range
    0..10.megabytes
  end

  version :thumb500 do
    process :resize_to_fit => [300, 300]
  end

  version :thumbnail do
    process resize_to_fit: [200, 200]
  end

  # Make version uploaders (thumb500_, thumbnail_) share the parent's
  # filename. Without this, when a subclass like UserAvatarUploader
  # overrides `filename` (to store at `<token>.jpg`), the parent file
  # lands at `<token>.jpg` but versions land at `thumb500_<original>.jpg`
  # — because CarrierWave's Versions#full_filename passes the version's
  # cached `@filename` (= the user-supplied original_filename) to super,
  # not the parent's renamed filename. The result is `image.thumb500.url`
  # resolving to a 403/404 because no file was ever stored at that key.
  #
  # Versions don't inherit from the subclass — they're rooted in this
  # parent class — so this override has to live here. `parent_version`
  # is CarrierWave's own back-link from a version uploader to its parent
  # (set in `versions` when the version is instantiated), and is nil for
  # the parent itself — so the parent path is unchanged. Subclasses
  # without a custom `filename` (no token rename) fall back to `for_file`,
  # which is identical to the default Versions behavior.
  def full_filename(for_file)
    parent_filename = parent_version&.filename
    super(parent_filename.presence || for_file)
  end

  process :strip

  def strip
    manipulate! do |img|
      img.strip!
      img = yield(img) if block_given?
      img
    end
  end

  def update_thumbnail (thumbnail)
    begin
      thumbnail.original_filename = thumbnail.original_filename.gsub 'thumb500_', ''
    rescue
    end

    begin
      store!(thumbnail)
      resize_to_fit(200, 200)
      store!
    rescue
    end
  end

  def clear_thumbnails
    # binding.pry
    if(File.directory?(store_dir.gsub('..', Rails.root.to_s)))
      items = []
      Dir.foreach(store_dir.gsub('..', Rails.root.to_s)) do |item|
        next if item == '.' or item == '..'
        items.push(item)
      end

      items.each do |item|
        origin_file = item.gsub('thumbnail_', '')
        if (item.include?('thumbnail_') && !items.include?(origin_file))
          File.delete(store_dir.gsub('..', Rails.root.to_s) + '/' + item)
        end
      end
    end
  end


end
