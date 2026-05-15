require 'rails_helper'

RSpec.describe UserAvatarUploader, type: :uploader do
  let(:user) do
    user_double = User.new(id: 12345)
    user_double.define_singleton_method(:save) { true }
    user_double
  end

  def upload_file(name)
    File.open(Rails.root.join('spec', 'support', 'logo-image.png')) do |f|
      sanitized = ActionDispatch::Http::UploadedFile.new(
        tempfile: f,
        filename: name,
        type: 'image/png'
      )
      uploader = described_class.new(user, :image)
      uploader.cache!(sanitized)
      uploader
    end
  end

  describe '#filename' do
    it 'returns a uuid-shaped name preserving the extension' do
      uploader = upload_file('myface.png')
      expect(uploader.filename).to match(/\A[0-9a-f-]{36}\.png\z/)
    end

    it 'returns the same filename across repeated calls within one upload' do
      uploader = upload_file('myface.png')
      first = uploader.filename
      second = uploader.filename
      third = uploader.filename
      expect(first).to eq(second)
      expect(second).to eq(third)
    end

    it 'lowercases the extension' do
      uploader = upload_file('Photo.JPEG')
      expect(uploader.filename).to match(/\.jpeg\z/)
    end

    it 'returns nil when there is no original_filename' do
      uploader = described_class.new(user, :image)
      expect(uploader.filename).to be_nil
    end
  end

  describe 'two uploads on the same user' do
    it 'gets distinct filenames so old object is removed instead of overwritten' do
      first  = upload_file('avatar1.png').filename
      # Reset the per-upload memoized token so the second upload behaves like
      # a fresh request (the model instance var is reset between requests in
      # production because each request loads a new User from the DB).
      user.instance_variable_set(:@user_avatar_secure_token, nil)
      second = upload_file('avatar2.png').filename
      expect(first).not_to eq(second)
    end
  end

  # Regression — versions used to be stored at `thumb500_<original>.png`
  # while User#avatar_url resolved to `thumb500_<token>.png`, leaving the
  # rendered thumb URL pointing at a non-existent S3 object. The fix makes
  # version uploaders share the parent's token-based filename so both
  # halves agree.
  describe '#full_filename — version filename pairing' do
    it 'prefixes version_name onto the parent token-based filename' do
      uploader = upload_file('myface.png')
      parent_filename = uploader.filename
      thumb500_filename = uploader.thumb500.send(:full_filename,'myface.png')
      thumbnail_filename = uploader.thumbnail.send(:full_filename,'myface.png')

      expect(parent_filename).to match(/\A[0-9a-f-]{36}\.png\z/)
      expect(thumb500_filename).to eq("thumb500_#{parent_filename}")
      expect(thumbnail_filename).to eq("thumbnail_#{parent_filename}")
    end

    it 'falls back to for_file when filename is nil (recreate_versions! path)' do
      # An uploader instance without an in-progress upload has no
      # original_filename, so `filename` returns nil. recreate_versions!
      # passes the stored parent identifier as `for_file`; we should use
      # that, not lose it to nil.
      uploader = described_class.new(user, :image)
      expect(uploader.filename).to be_nil
      expect(uploader.send(:full_filename,'stored-uuid.png')).to eq('stored-uuid.png')
      expect(uploader.thumb500.send(:full_filename,'stored-uuid.png')).to eq('thumb500_stored-uuid.png')
    end
  end
end
