module Notifications
  # Central registry mapping event symbols to message templates and navigation targets.
  #
  # Adding a new event:
  #   1. Add an entry here with :message, :target_type, :target_screen, and :target_id.
  #   2. Call Notifications.publish!(event: :your_event, ...) from the feature call site.
  #
  # Lambdas receive keyword args:  actor:, resource:, metadata:
  #   - actor    = the User who triggered the event
  #   - resource = the domain object (ItemRequest, Order, Trustline, etc.)
  #   - metadata = extra hash passed by the call site
  module EventRegistry
    EVENTS = {
      request_created: {
        message:       ->(actor:, resource:, **) {
          item_name = resource.request_contract.inventory.item.name rescue 'an item'
          "#{actor.user_name} requested #{item_name}"
        },
        target_type:   'item',
        target_screen: 'item_detail',
        target_id:     ->(resource:, **) { resource.request_contract.inventory_id }
      }

      # Future events follow the same shape:
      #
      # request_accepted: { ... },
      # request_cancelled: { ... },
      # order_shipped: { ... },
      # order_signed: { ... },
      # settlement_proposed: { ... },
      # settlement_completed: { ... },
      # payment_received: { ... },
      # trustline_created: { ... },
      # invitation_accepted: { ... },
    }.freeze

    def self.fetch(event)
      EVENTS.fetch(event) { raise ArgumentError, "Unknown notification event: #{event}" }
    end
  end
end
