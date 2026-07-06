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
  #
  # Obligation keys (actionable events):
  #   - subject:       extracts the obligation object from the publish args; persisted on the
  #                    notification row as subject_type/subject_id
  #   - resolved_when: pure derivation from current domain state; returns a resolution reason
  #                    symbol, or nil while the obligation is still outstanding
  #
  # Future informational/FYI events (e.g. request_accepted, payment_received) that require no
  # action from the recipient should declare:
  #   resolved_when: ->(**) { :informational }
  # evaluated at publish time (the row is born resolved). No v1 decision is forced; this shape
  # accommodates it.
  module EventRegistry
    EVENTS = {
      request_created: {
        message:       ->(actor:, resource:, **) {
          item_name = resource.request_contract.inventory.item.name rescue 'an item'
          "#{actor.user_name} requested #{item_name}"
        },
        target_type:   'item',
        target_screen: 'item_detail',
        target_id:     ->(resource:, **) { resource.request_contract.inventory_id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(subject:, **) {
          return :orphaned   if subject.nil? || subject.destroyed?
          return :accepted   if subject.accepted? || subject.completed?
          return :cancelled  if subject.cancelled?
          contract = subject.request_contract
          return :cancelled  if contract.nil? || contract.cancelled?
          nil
        }
      },

      pending_payment_created: {
        message:       ->(actor:, resource:, **) {
          "#{actor.user_name} sent you $#{format('%.2f', resource.amount)}"
        },
        target_type:   'trustline',
        target_screen: 'trustlines',
        target_id:     ->(resource:, **) { resource.trustline_id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(subject:, **) {
          return :orphaned   if subject.nil? || subject.destroyed?
          return :confirmed  if subject.confirmed?
          return :rejected   if subject.rejected?
          return :cancelled  if subject.cancelled?
          nil  # outstanding while pending?
        }
      },

      payment_request_created: {
        message:       ->(actor:, resource:, **) {
          "#{actor.user_name} is requesting $#{format('%.2f', resource.amount)} in cash"
        },
        target_type:   'trustline',
        target_screen: 'trustlines',
        target_id:     ->(resource:, **) { resource.trustline_id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(subject:, **) {
          return :orphaned   if subject.nil? || subject.destroyed?
          return :paid       if subject.paid_pending_confirmation? || subject.confirmed?
          return :rejected   if subject.rejected?
          return :cancelled  if subject.cancelled?
          nil  # outstanding while pending?
        }
      },

      payment_request_paid: {
        message:       ->(actor:, resource:, **) {
          "#{actor.user_name} paid your $#{format('%.2f', resource.amount)} request — confirm receipt"
        },
        target_type:   'trustline',
        target_screen: 'trustlines',
        target_id:     ->(resource:, **) { resource.trustline_id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(subject:, **) {
          return :orphaned   if subject.nil? || subject.destroyed?
          return :confirmed  if subject.confirmed?
          return :rejected   if subject.rejected?
          return :cancelled  if subject.cancelled?
          nil  # outstanding while paid_pending_confirmation?
        }
      },

      # --- Contact introductions ---

      introduction_requested: {
        message:       ->(actor:, metadata:, **) {
          "#{actor.user_name} would like to introduce you to #{metadata[:other_introducee_name]}"
        },
        target_type:   'introduction',
        target_screen: 'introduction_detail',
        target_id:     ->(resource:, **) { resource.id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(subject:, notification:, **) {
          return :orphaned if subject.nil? || subject.destroyed?
          return :declined if subject.declined?
          return :accepted if subject.completed?
          return :accepted if subject.accepted_by?(notification.recipient_id)  # this party fulfilled their side
          nil  # pending and this party hasn't acted yet
        }
      },

      introduction_completed: {
        message:       ->(metadata:, **) {
          if metadata[:other_introducee_name]
            "You're now connected to #{metadata[:other_introducee_name]}"
          else
            "Your introduction of #{metadata[:introducee_a_name]} and #{metadata[:introducee_b_name]} worked — they're now connected"
          end
        },
        target_type:   'introduction',
        target_screen: 'introduction_detail',
        target_id:     ->(resource:, **) { resource.id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(**) { :informational }
      },

      introduction_declined: {
        message:       ->(actor:, **) { "#{actor.user_name} declined your introduction" },
        target_type:   'introduction',
        target_screen: 'introduction_detail',
        target_id:     ->(resource:, **) { resource.id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(**) { :informational }
      },

      # --- Connection requests (general connect handshake; Local Discovery's first caller) ---

      connection_requested: {
        message:       ->(actor:, **) { "#{actor.user_name} wants to connect with you" },
        target_type:   'connection_request',
        target_screen: 'connection_requests',
        target_id:     ->(resource:, **) { resource.id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(subject:, **) {
          return :orphaned   if subject.nil? || subject.destroyed?
          return :accepted   if subject.accepted?
          return :declined   if subject.declined?
          nil
        }
      },

      connection_accepted: {
        message:       ->(actor:, **) { "#{actor.user_name} accepted your connection request" },
        target_type:   'connection_request',
        target_screen: 'connection_requests',
        target_id:     ->(resource:, **) { resource.id },
        subject:       ->(resource:, **) { resource },
        resolved_when: ->(**) { :informational }
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
