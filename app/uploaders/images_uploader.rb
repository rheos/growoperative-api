require 'carrierwave/processing/rmagick'

class ImagesUploader < CarrierWave::Uploader::Base
  # Include RMagick or MiniMagick support:
  include CarrierWave::RMagick


  # Choose what kind of storage to use for this uploader:
  storage :file
  # storage :fog

  # Override the directory where uploaded files will be stored.
  # This is a sensible default for uploaders that are meant to be mounted:
  def store_dir
    "../private/uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end

  # Provide a default URL as a default if there hasn't been a file uploaded:
  # def default_url(*args)
  #   # For Rails 3.1+ asset pipeline compatibility:
  #   # ActionController::Base.helpers.asset_path("fallback/" + [version_name, "default.png"].compact.join('_'))
  #
  #   "/images/fallback/" + [version_name, "default.png"].compact.join('_')
  # end

  # Process files as they are uploaded:
  # process scale: [200, 300]
  #
  # def scale(width, height)
  #   # do something
  # end

  # Create different versions of your uploaded files:
  # version :thumb do
  #   process resize_to_fit: [50, 50]
  # end

  process :strip

  def strip
    manipulate! do |img|
      img.strip!
      img = yield(img) if block_given?
      img
    end
  end

  def update_thumbnail (thumbnail, origin_names = nil)
    store!(thumbnail)
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

  # Add a white list of extensions which are allowed to be uploaded.
  # For images you might use something like this:
  # def extension_whitelist
  #   %w(jpg jpeg gif png)
  # end

  # Override the filename of the uploaded files:
  # Avoid using model.id or version_name here, see uploader/store.rb for details.
  # def filename
  #   "something.jpg" if original_filename
  # end
end
