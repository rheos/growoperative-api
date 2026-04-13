require 'rails_helper'

RSpec.describe 'Notifications API', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:user) do
    User.create!(user_name: 'notif_testuser', password: password)
  end
  let(:actor) { User.create!(user_name: 'notif_alice', password: password) }
  let(:token) { "Bearer #{JwtGenerationService.new(user_id: user.id).token}" }
  let(:auth_headers) { { 'Authorization' => token } }

  def create_notification(attrs = {})
    Notification.create!({
      recipient:         user,
      actor:             actor,
      notification_type: 'request_created',
      message:           'alice requested tomatoes',
      actor_name:        'alice',
      target_type:       'item',
      target_id:         1,
      target_screen:     'item_detail'
    }.merge(attrs))
  end

  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe 'GET /v1/notifications' do
    it 'returns paginated notifications newest-first' do
      old = create_notification(message: 'old', created_at: 2.hours.ago)
      new_one = create_notification(message: 'new', created_at: 1.minute.ago)

      get '/v1/notifications', headers: auth_headers
      expect(response).to have_http_status(200)

      body = JSON.parse(response.body)
      expect(body['data'].length).to eq(2)
      expect(body['data'][0]['id']).to eq(new_one.id)
      expect(body['data'][1]['id']).to eq(old.id)
      expect(body['meta']['has_more']).to eq(false)
    end

    it 'returns correct notification shape' do
      create_notification(metadata: { 'quantity' => 10 })

      get '/v1/notifications', headers: auth_headers
      body = JSON.parse(response.body)
      n = body['data'].first

      expect(n.keys).to contain_exactly(
        'id', 'type', 'message', 'actor_name', 'actor_avatar_url',
        'target_type', 'target_id', 'target_screen', 'metadata',
        'read', 'read_at', 'created_at'
      )
      expect(n['type']).to eq('request_created')
      expect(n['read']).to eq(false)
      expect(n['metadata']).to eq({ 'quantity' => 10 })
    end

    it 'paginates with has_more' do
      (Notification::PAGE_SIZE + 1).times do |i|
        create_notification(message: "msg #{i}", created_at: i.minutes.ago)
      end

      get '/v1/notifications?page=1', headers: auth_headers
      body = JSON.parse(response.body)
      expect(body['data'].length).to eq(Notification::PAGE_SIZE)
      expect(body['meta']['has_more']).to eq(true)

      get '/v1/notifications?page=2', headers: auth_headers
      body = JSON.parse(response.body)
      expect(body['data'].length).to eq(1)
      expect(body['meta']['has_more']).to eq(false)
    end

    it 'requires authentication' do
      get '/v1/notifications'
      expect(response).to have_http_status(401)
    end
  end

  describe 'GET /v1/notifications/unread_count' do
    it 'returns the count of unread notifications' do
      create_notification(read: false)
      create_notification(read: false)
      create_notification(read: true, read_at: Time.current)

      get '/v1/notifications/unread_count', headers: auth_headers
      body = JSON.parse(response.body)
      expect(body['unread_count']).to eq(2)
    end
  end

  describe 'PATCH /v1/notifications/:id/read' do
    it 'marks a notification as read' do
      n = create_notification

      patch "/v1/notifications/#{n.id}/read", headers: auth_headers
      expect(response).to have_http_status(200)

      n.reload
      expect(n.read).to eq(true)
      expect(n.read_at).to be_present
    end

    it 'returns 404 for another user notification' do
      other_user = User.create!(user_name: 'notif_other', password: password)
      n = create_notification(recipient: other_user)

      patch "/v1/notifications/#{n.id}/read", headers: auth_headers
      expect(response).to have_http_status(404)
    end
  end

  describe 'PATCH /v1/notifications/read_all' do
    it 'marks all unread notifications as read' do
      create_notification(read: false)
      create_notification(read: false)
      create_notification(read: true, read_at: Time.current)

      patch '/v1/notifications/read_all', headers: auth_headers
      expect(response).to have_http_status(200)

      expect(user.notifications.unread.count).to eq(0)
      expect(user.notifications.where(read: true).count).to eq(3)
    end
  end
end
