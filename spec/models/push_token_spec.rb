require 'rails_helper'

RSpec.describe PushToken, type: :model, skip_hooks: true do
  let(:user)  { User.create!(user_name: 'push_bob', password: 'password123') }
  let(:other) { User.create!(user_name: 'push_alice', password: 'password123') }

  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  def build_token(attrs = {})
    PushToken.new({
      user:      user,
      token:     'ExponentPushToken[aaaaaaaaaaaaaaaaaaaaaa]',
      device_id: 'device-1',
      platform:  'ios'
    }.merge(attrs))
  end

  describe 'validations' do
    it 'is valid with required fields' do
      expect(build_token).to be_valid
    end

    it 'requires token' do
      pt = build_token(token: nil)
      expect(pt).not_to be_valid
      expect(pt.errors[:token]).to be_present
    end

    it 'requires device_id' do
      pt = build_token(device_id: nil)
      expect(pt).not_to be_valid
      expect(pt.errors[:device_id]).to be_present
    end

    it 'requires platform' do
      pt = build_token(platform: nil)
      expect(pt).not_to be_valid
      expect(pt.errors[:platform]).to be_present
    end

    it 'rejects a platform outside ios/android' do
      pt = build_token(platform: 'web')
      expect(pt).not_to be_valid
      expect(pt.errors[:platform]).to be_present
    end

    it 'accepts ios and android' do
      expect(build_token(platform: 'ios')).to be_valid
      expect(build_token(platform: 'android', device_id: 'device-2', token: 'ExponentPushToken[bbbbbbbbbbbbbbbbbbbbbb]')).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs_to :user' do
      assoc = PushToken.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end
  end

  describe 'unique index on token' do
    it 'rejects a second row with the same token string' do
      build_token.save!

      dup = build_token(user: other, device_id: 'device-2')
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'composite unique index on (user_id, device_id)' do
    it 'rejects a second row for the same user + device_id' do
      build_token.save!

      dup = build_token(token: 'ExponentPushToken[cccccccccccccccccccccc]')
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same device_id for a different user' do
      build_token.save!

      same_device_other_user = build_token(
        user:  other,
        token: 'ExponentPushToken[dddddddddddddddddddddd]'
      )
      expect { same_device_other_user.save! }.not_to raise_error
    end
  end
end
