class UserAvatarUploader < ImagesUploader
  # Randomize the stored filename per upload. Each new avatar lands at a
  # fresh S3 path, which:
  #   1. Makes browser caches invalidate naturally (no longer same URL with
  #      new content).
  #   2. Lets CarrierWave's default remove_previously_stored_files_after_update
  #      callback actually delete the prior object (default deletion only
  #      fires when the new filename differs from the old).
  #   3. Avoids cross-user filename collisions if two users uploaded
  #      "avatar.jpg" with overlapping ids — the path is fully unique.
  #
  # Versions (thumb500_, thumbnail_) share the parent uploader's model, so
  # they pick up the same secure_token and produce matching base filenames.
  def filename
    "#{secure_token}#{File.extname(original_filename).downcase}" if original_filename.present?
  end

  protected

  def secure_token
    model.instance_variable_get(:@user_avatar_secure_token) ||
      model.instance_variable_set(:@user_avatar_secure_token, SecureRandom.uuid)
  end
end
