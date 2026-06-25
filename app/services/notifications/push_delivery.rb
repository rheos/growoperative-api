require 'net/http'
require 'json'

module Notifications
  # Best-effort push delivery for freshly-published notifications.
  #
  # Called from Publisher.call AFTER Notifications.resolve!(subject) runs, so the
  # in-memory notifications array's resolved_at is stale (the resolver re-loads
  # records and stamps those, never the in-memory objects). We therefore receive
  # only the row IDs and re-query post-resolve truth — see B1 below.
  #
  # Delivery is fire-and-forget on a bounded thread pool; failures are logged,
  # never raised. A blank EXPO_ACCESS_TOKEN short-circuits the whole thing so dev
  # and demo no-op without any extra flag.
  class PushDelivery
    EXPO_PUSH_URL = URI('https://exp.host/--/api/v2/push/send').freeze

    # Title is a short category label; the body carries the notification's own
    # descriptive message ("peter requested Black Krim", etc.) so the push is
    # self-explanatory without opening the app. NOTE: that message includes names
    # and item names, which surface on the lock screen — an accepted product
    # tradeoff for clarity (the body was previously a generic PII-free string).
    PUSH_TITLES = {
      'request_created'         => 'New item request',
      'pending_payment_created' => 'Incoming payment',
      'payment_request_created' => 'Payment request',
      'payment_request_paid'    => 'Payment received',
    }.freeze

    # Bounded queue so a flood applies real backpressure: once max_queue is hit,
    # :caller_runs runs the task on the calling thread instead of growing memory.
    # An unbounded (default max_queue: 0) pool would never trigger :caller_runs.
    POOL = Concurrent::FixedThreadPool.new(4, max_queue: 100, fallback_policy: :caller_runs)

    def self.deliver(ids)
      return if ENV['EXPO_ACCESS_TOKEN'].blank?

      POOL.post do
        begin
          # W3: every DB touch inside the pool task runs inside a checked-out
          # connection, or the thread leaks a connection under Puma.
          ActiveRecord::Base.connection_pool.with_connection do
            # B1: Re-load post-resolve truth. The in-memory notifications array is
            # stale — resolver.rb stamps freshly-loaded records, not those objects.
            notifications = Notification.where(id: ids).unresolved.includes(:recipient)

            notifications.group_by(&:recipient).each do |recipient, recipient_notifications|
              tokens = PushToken.where(user: recipient)
              next if tokens.empty?

              badge = Notification.where(recipient: recipient).unresolved.count

              tokens.each do |push_token|
                recipient_notifications.each do |notification|
                  send_one(push_token, notification, badge)
                end
              end
            end
          end
        rescue => e
          Rails.logger.error("[Notifications::PushDelivery] error: #{e.message}")
        end
      end
    end

    def self.send_one(push_token, notification, badge)
      payload = [{
        to:    push_token.token,
        title: PUSH_TITLES.fetch(notification.notification_type, 'New notification'),
        body:  notification.message,
        sound: 'default',
        badge: badge,
        data: {
          notificationId: notification.id,
          targetType:     notification.target_type,
          targetId:       notification.target_id,
          targetScreen:   notification.target_screen,
        },
      }]

      http = Net::HTTP.new(EXPO_PUSH_URL.host, EXPO_PUSH_URL.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(EXPO_PUSH_URL.path)
      request['Content-Type']  = 'application/json'
      request['Authorization'] = "Bearer #{ENV['EXPO_ACCESS_TOKEN']}"
      request.body = payload.to_json

      response    = http.request(request)
      body        = JSON.parse(response.body)
      ticket_data = body.dig('data', 0)
      return unless ticket_data.is_a?(Hash) && ticket_data['status'] == 'error'
      return unless ticket_data.dig('details', 'error') == 'DeviceNotRegistered'

      # W3: prune inside the same with_connection block (called from deliver which
      # already holds the connection).
      PushToken.where(token: push_token.token).delete_all
    end
    private_class_method :send_one
  end
end
