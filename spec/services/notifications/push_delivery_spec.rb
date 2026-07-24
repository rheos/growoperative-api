require 'rails_helper'
require 'securerandom'

# Unit coverage for Notifications::PushDelivery. The Expo HTTP call is stubbed at
# the Net::HTTP boundary — these specs never hit the network.
#
# The delivery body normally runs on a bounded thread pool (PushDelivery::POOL).
# We stub POOL.post to yield synchronously in the test thread so assertions are
# deterministic. The with_connection block still runs as written; it is a no-op
# wrapper around the test's existing checked-out connection.
#
# EXPO_ACCESS_TOKEN is set/restored with the project's save-restore convention
# (see jwt_hs256_bridge_sunset_spec.rb) — no ClimateControl gem is available.
RSpec.describe Notifications::PushDelivery, type: :model, skip_hooks: true do
  around(:each) do |example|
    previous = ENV['EXPO_ACCESS_TOKEN']
    example.run
    if previous.nil?
      ENV.delete('EXPO_ACCESS_TOKEN')
    else
      ENV['EXPO_ACCESS_TOKEN'] = previous
    end
  end

  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  # Run the pool task inline so assertions are synchronous.
  def run_pool_inline!
    allow(Notifications::PushDelivery::POOL).to receive(:post) do |&block|
      block.call
    end
  end

  # Capture every payload POSTed to Expo, and let the test control the response body.
  # Returns the array of decoded payloads (each is the [{...}] array PushDelivery sends).
  def stub_expo(response_body: { 'data' => [{ 'status' => 'ok' }] })
    captured = []
    fake_http = instance_double(Net::HTTP)
    allow(fake_http).to receive(:use_ssl=)
    allow(Net::HTTP).to receive(:new).and_return(fake_http)

    fake_response = instance_double(Net::HTTPResponse, body: response_body.to_json)
    allow(fake_http).to receive(:request) do |req|
      captured << JSON.parse(req.body)
      fake_response
    end
    captured
  end

  def create_user(prefix)
    User.create!(user_name: "#{prefix}-#{SecureRandom.hex(3)}", password: 'password123')
  end

  def create_notification(recipient, attrs = {})
    Notification.create!({
      recipient:         recipient,
      notification_type: 'request_created',
      message:           'something happened',
      target_type:       'item',
      target_id:         1,
      target_screen:     'item_detail'
    }.merge(attrs))
  end

  def register_token(user, token)
    PushToken.create!(user: user, token: token, device_id: "dev-#{SecureRandom.hex(3)}", platform: 'ios')
  end

  describe '.deliver' do
    context 'when EXPO_ACCESS_TOKEN is blank' do
      before { ENV['EXPO_ACCESS_TOKEN'] = '' }

      it 'returns immediately and never posts to the pool or calls Net::HTTP' do
        recipient = create_user('recip')
        register_token(recipient, 'ExponentPushToken[blankblankblankblankbl]')
        n = create_notification(recipient)

        expect(Notifications::PushDelivery::POOL).not_to receive(:post)
        expect(Net::HTTP).not_to receive(:new)

        Notifications::PushDelivery.deliver([n.id])
      end
    end

    context 'when EXPO_ACCESS_TOKEN is present' do
      before do
        ENV['EXPO_ACCESS_TOKEN'] = 'test-expo-token'
        run_pool_inline!
      end

      it 'excludes born-resolved rows by re-querying post-resolve (B1)' do
        recipient = create_user('recip')
        register_token(recipient, 'ExponentPushToken[b1b1b1b1b1b1b1b1b1b1b1]')

        live     = create_notification(recipient, message: 'still outstanding')
        resolved = create_notification(recipient, message: 'already done')

        # Stamp resolved_at on one row AFTER both are created — mirrors the
        # publish-time race the publisher closes with Notifications.resolve!.
        resolved.resolve!(:accepted)

        captured = stub_expo

        Notifications::PushDelivery.deliver([live.id, resolved.id])

        sent_ids = captured.flatten.map { |p| p.dig('data', 'notificationId') }
        expect(sent_ids).to eq([live.id])
        expect(sent_ids).not_to include(resolved.id)
      end

      it 'skips recipients with no push tokens' do
        recipient = create_user('recip')
        n = create_notification(recipient)

        expect(Net::HTTP).not_to receive(:new)

        Notifications::PushDelivery.deliver([n.id])
      end

      it 'prunes a token on DeviceNotRegistered' do
        recipient = create_user('recip')
        token_str = 'ExponentPushToken[deaddeaddeaddeaddeadde]'
        register_token(recipient, token_str)
        n = create_notification(recipient)

        stub_expo(response_body: {
          'data' => [{ 'status' => 'error', 'details' => { 'error' => 'DeviceNotRegistered' } }]
        })

        expect {
          Notifications::PushDelivery.deliver([n.id])
        }.to change { PushToken.where(token: token_str).count }.from(1).to(0)
      end

      it 'sends the category title, message body, and notification id in data' do
        recipient = create_user('recip')
        register_token(recipient, 'ExponentPushToken[okokokokokokokokokokok]')
        n = create_notification(recipient, notification_type: 'request_created')

        captured = stub_expo

        Notifications::PushDelivery.deliver([n.id])

        payload = captured.flatten.first
        expect(payload['title']).to eq('New item request')
        expect(payload['body']).to eq('something happened')
        expect(payload.dig('data', 'notificationId')).to eq(n.id)
      end

      it 'logs and does not raise when the pool task body throws' do
        recipient = create_user('recip')
        register_token(recipient, 'ExponentPushToken[throwthrowthrowthrowth]')
        n = create_notification(recipient)

        # Force a failure inside the with_connection block.
        allow(Notification).to receive(:where).and_raise(StandardError, 'db boom')
        expect(Rails.logger).to receive(:error).with(/PushDelivery/)

        expect { Notifications::PushDelivery.deliver([n.id]) }.not_to raise_error
      end
    end
  end

  describe 'Publisher hook (publisher.rb)' do
    before { ENV['EXPO_ACCESS_TOKEN'] = 'test-expo-token' }

    # The hook line `Notifications::PushDelivery.deliver(...)` runs synchronously
    # inside Publisher.call, but deliver() is a thin non-raising dispatch: it posts
    # the work to POOL and returns. The error isolation that matters in production
    # lives in the pool task's rescue (covered above). Here we confirm the hook
    # fires with the freshly-created row ids and does not disturb Publisher.call's
    # return value.
    #
    # We stub EventRegistry.fetch with a minimal, resource-free event so the test
    # owns no domain wiring — the publisher under test is the subject, not the
    # request_created registry lambdas (which dereference resource.request_contract
    # and require a real ItemRequest graph).
    it 'fires deliver with the created row ids and still returns the notifications' do
      actor     = create_user('actor')
      recipient = create_user('recip')

      allow(Notifications::EventRegistry).to receive(:fetch).and_return(
        message:       'hook test message',
        target_type:   'system',
        target_screen: nil,
        target_id:     nil,
        subject:       nil
      )

      # Stub the pool so the posted task never actually runs (no network).
      allow(Notifications::PushDelivery::POOL).to receive(:post)

      delivered_ids = nil
      allow(Notifications::PushDelivery).to receive(:deliver) do |ids|
        delivered_ids = ids
      end

      result = Notifications::Publisher.call(
        event:      :hook_test_event,
        actor:      actor,
        recipients: [recipient],
        resource:   nil,
        metadata:   {}
      )

      expect(result.first.recipient_id).to eq(recipient.id)
      expect(delivered_ids).to eq(result.map(&:id))
    end
  end
end
