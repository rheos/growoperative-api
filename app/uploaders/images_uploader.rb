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
