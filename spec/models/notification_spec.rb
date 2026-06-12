require 'rails_helper'

RSpec.describe Notification, type: :model, skip_hooks: true do
  let(:recipient) { User.create!(user_name: 'notif_bob', password: 'password123') }
  let(:actor)     { User.create!(user_name: 'notif_alice', password: 'password123') }

  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe 'validations' do
    it 'requires notification_type' do
      n = Notification.new(recipient: recipient, message: 'hi')
      expect(n).not_to be_valid
      expect(n.errors[:notification_type]).to be_present
    end

    it 'requires message' do
      n = Notification.new(recipient: recipient, notification_type: 'system')
      expect(n).not_to be_valid
      expect(n.errors[:message]).to be_present
    end

    it 'is valid with required fields' do
      n = Notification.new(recipient: recipient, notification_type: 'system', message: 'hello')
      expect(n).to be_valid
    end
  end

  describe '#mark_read!' do
    it 'sets read and read_at' do
      n = Notification.create!(recipient: recipient, notification_type: 'system', message: 'hi')
      expect(n.read).to eq(false)

      n.mark_read!
      n.reload
      expect(n.read).to eq(true)
      expect(n.read_at).to be_present
    end

    it 'is idempotent' do
      n = Notification.create!(recipient: recipient, notification_type: 'system', message: 'hi')
      n.mark_read!
      original_read_at = n.read_at

      n.mark_read!
      expect(n.read_at).to eq(original_read_at)
    end
  end

  describe '#as_inbox_json' do
    it 'returns the expected shape' do
      n = Notification.create!(
        recipient:         recipient,
        actor:             actor,
        notification_type: 'request_created',
        message:           'alice requested tomatoes',
        actor_name:        'alice',
        actor_avatar_url:  nil,
        target_type:       'item',
        target_id:         42,
        target_screen:     'item_detail',
        metadata:          { 'quantity' => 10 }
      )

      json = n.as_inbox_json
      expect(json[:id]).to eq(n.id)
      expect(json[:type]).to eq('request_created')
      expect(json[:message]).to eq('alice requested tomatoes')
      expect(json[:actor_name]).to eq('alice')
      expect(json[:target_type]).to eq('item')
      expect(json[:target_id]).to eq(42)
      expect(json[:target_screen]).to eq('item_detail')
      expect(json[:metadata]).to eq({ 'quantity' => 10 })
      expect(json[:read]).to eq(false)
      expect(json[:read_at]).to be_nil
      expect(json[:created_at]).to be_a(String)
    end
  end

  describe 'resolution' do
    let(:notification) do
      Notification.create!(
        recipient:         recipient,
        notification_type: 'request_created',
        message:           'alice requested tomatoes',
        subject_type:      'ItemRequest',
        subject_id:        7
      )
    end

    describe '#resolve!' do
      it 'sets resolved_at and resolution_reason on an unresolved notification' do
        expect(notification.resolved_at).to be_nil

        notification.resolve!(:accepted)
        notification.reload

        expect(notification.resolved_at).to be_present
        expect(notification.resolution_reason).to eq('accepted')
      end

      it 'is idempotent — a second call with a different reason is a no-op' do
        notification.resolve!(:accepted)
        notification.reload
        first_resolved_at = notification.resolved_at

        notification.resolve!(:cancelled)
        notification.reload

        expect(notification.resolved_at).to eq(first_resolved_at)
        expect(notification.resolution_reason).to eq('accepted')
      end
    end

    describe '.unresolved' do
      it 'returns only rows where resolved_at is nil' do
        live     = notification
        resolved = Notification.create!(recipient: recipient, notification_type: 'system', message: 'done')
        resolved.resolve!(:paid)

        expect(Notification.unresolved).to include(live)
        expect(Notification.unresolved).not_to include(resolved)
      end
    end

    describe '#as_inbox_json resolution fields' do
      it 'serializes an unresolved notification as outstanding' do
        json = notification.as_inbox_json

        expect(json[:subject_type]).to eq('ItemRequest')
        expect(json[:subject_id]).to eq(7)
        expect(json[:resolved_at]).to be_nil
        expect(json[:resolution_reason]).to be_nil
        expect(json[:outstanding]).to eq(true)
      end

      it 'serializes a resolved notification with reason and ISO8601 timestamp' do
        notification.resolve!(:confirmed)
        json = notification.reload.as_inbox_json

        expect(json[:subject_type]).to eq('ItemRequest')
        expect(json[:subject_id]).to eq(7)
        expect(json[:resolved_at]).to eq(notification.resolved_at.iso8601)
        expect(json[:resolved_at]).to be_a(String)
        expect(json[:resolution_reason]).to eq('confirmed')
        expect(json[:outstanding]).to eq(false)
      end
    end
  end

  describe 'scopes' do
    before do
      Notification.create!(recipient: recipient, notification_type: 'system', message: 'old', created_at: 1.hour.ago)
      Notification.create!(recipient: recipient, notification_type: 'system', message: 'new', created_at: 1.minute.ago)
      Notification.create!(recipient: recipient, notification_type: 'system', message: 'read', read: true, read_at: Time.current, created_at: 30.minutes.ago)
    end

    it '.newest_first orders by created_at desc' do
      messages = recipient.notifications.newest_first.pluck(:message)
      expect(messages).to eq(['new', 'read', 'old'])
    end

    it '.unread returns only unread' do
      expect(recipient.notifications.unread.count).to eq(2)
    end
  end
end
