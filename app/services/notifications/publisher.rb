module Notifications
  # Single entry point for creating notifications.
  #
  # Usage (one-liner at the call site):
  #
  #   Notifications.publish!(
  #     event:      :request_created,
  #     actor:      current_user,
  #     recipients: [item_owner],
  #     resource:   item_request,
  #     metadata:   { quantity: 10 }
  #   )
  #
  # What happens under the hood:
  #   1. Looks up event config from EventRegistry (message template, target info)
  #   2. Evaluates the message lambda once (same message for all recipients)
  #   3. Builds one Notification row per recipient
  #   4. Skips the actor (you don't notify yourself)
  #   5. Future: evaluate per-recipient delivery preferences here
  #
  module Publisher
    def self.call(event:, actor:, recipients:, resource: nil, metadata: {})
      config = EventRegistry.fetch(event)

      message    = resolve(config[:message],    actor: actor, resource: resource, metadata: metadata)
      target_id  = resolve(config[:target_id],  actor: actor, resource: resource, metadata: metadata)

      actor_name       = actor.user_name
      actor_avatar_url = actor.avatar_url

      notifications = []

      Array(recipients).uniq.each do |recipient|
        # Don't notify the person who triggered the event
        next if recipient.id == actor.id

        # Future hook: check recipient preferences here
        # next if recipient_opted_out?(recipient, event)

        notifications << Notification.create!(
          recipient:        recipient,
          actor:            actor,
          notification_type: event.to_s,
          message:          message,
          actor_name:       actor_name,
          actor_avatar_url: actor_avatar_url,
          target_type:      config[:target_type],
          target_id:        target_id,
          target_screen:    config[:target_screen],
          metadata:         metadata.presence
        )
      end

      notifications
    end

    def self.resolve(value, **kwargs)
      value.respond_to?(:call) ? value.call(**kwargs) : value
    end
    private_class_method :resolve
  end
end
