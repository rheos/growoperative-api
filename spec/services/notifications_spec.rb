require 'rails_helper'

RSpec.describe Notifications, type: :model, skip_hooks: true do
  let(:actor)      { User.create!(user_name: 'alice', password: 'password123') }
  let(:recipient1) { User.create!(user_name: 'bob',   password: 'password123') }
  let(:recipient2) { User.create!(user_name: 'carol', password: 'password123') }

  # Minimal object graph for request_created event
  let(:grade)    { Grade.create!(name: 'A', value: 30) }
  let(:item_unit) { ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592) }
  let(:category) { Category.create!(category_name: 'greens', default_unit: item_unit, kind: :produce, default_node_price: 1.0) }
  let(:item_name) { ItemName.create!(name: 'Tomatoes', category: category) }
  let(:item) do
    Item.create!(
      user: actor, category: category, item_name: item_name,
      grade: grade, item_unit: item_unit, name: 'Tomatoes', price: 5.0, quantity: 100
    )
  end
  let(:inventory) do
    Inventory.create!(user: actor, item: item, quantity: 100, price: 5, status: :available)
  end
  let(:request_contract) do
    RequestContract.create!(user: actor, item: item, inventory_id: inventory.id, quantity: 10, steps: 1)
  end
  let(:item_request) do
    ItemRequest.create!(
      user: actor, friend: recipient1,
      request_contract: request_contract,
      price: 5, status: :pending, step: 1
    )
  end

  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe '.publish!' do
    it 'creates one notification per recipient' do
      expect {
        Notifications.publish!(
          event:      :request_created,
          actor:      actor,
          recipients: [recipient1, recipient2],
          resource:   item_request,
          metadata:   { request_contract_id: request_contract.id }
        )
      }.to change(Notification, :count).by(2)
    end

    it 'skips the actor when actor is in the recipient list' do
      expect {
        Notifications.publish!(
          event:      :request_created,
          actor:      actor,
          recipients: [actor, recipient1],
          resource:   item_request,
          metadata:   {}
        )
      }.to change(Notification, :count).by(1)

      expect(Notification.last.recipient).to eq(recipient1)
    end

    it 'deduplicates recipients' do
      expect {
        Notifications.publish!(
          event:      :request_created,
          actor:      actor,
          recipients: [recipient1, recipient1],
          resource:   item_request,
          metadata:   {}
        )
      }.to change(Notification, :count).by(1)
    end

    it 'populates all notification fields correctly' do
      Notifications.publish!(
        event:      :request_created,
        actor:      actor,
        recipients: [recipient1],
        resource:   item_request,
        metadata:   { quantity: 10.0 }
      )

      n = Notification.last
      expect(n.notification_type).to eq('request_created')
      expect(n.message).to include('alice')
      expect(n.message).to include('Tomatoes')
      expect(n.actor_name).to eq('alice')
      expect(n.target_type).to eq('item')
      expect(n.target_id).to eq(inventory.id)
      expect(n.target_screen).to eq('item_detail')
      expect(n.recipient).to eq(recipient1)
      expect(n.actor).to eq(actor)
      expect(n.read).to eq(false)
    end

    it 'raises on unknown event' do
      expect {
        Notifications.publish!(
          event: :bogus_event, actor: actor, recipients: [recipient1]
        )
      }.to raise_error(ArgumentError, /Unknown notification event/)
    end

    it 'persists the subject link on each created row' do
      Notifications.publish!(
        event:      :request_created,
        actor:      actor,
        recipients: [recipient1],
        resource:   item_request,
        metadata:   {}
      )

      n = Notification.last
      expect(n.subject_type).to eq('ItemRequest')
      expect(n.subject_id).to eq(item_request.id)
    end

    it 'publishes request_accepted as a born-resolved FYI to the requester' do
      Notifications.publish!(
        event:      :request_accepted,
        actor:      actor,        # the party who accepted (the owner)
        recipients: [recipient1], # the original requester
        resource:   item_request
      )

      n = Notification.last
      expect(n.notification_type).to eq('request_accepted')
      expect(n.message).to eq('alice accepted your request for Tomatoes')
      expect(n.target_type).to eq('item')
      expect(n.target_screen).to eq('item_detail')
      expect(n.target_id).to eq(inventory.id)
      expect(n.recipient).to eq(recipient1)
      expect(n.subject_type).to eq('ItemRequest')
      expect(n.resolved_at).to be_present   # FYI is born resolved (:informational)
    end

    it 'publishes settlement_proposed as an actionable notification to the receiver' do
      order = Order.create!(user_id: recipient1.id, friend_id: actor.id,
                            order_status: :pending, settlement_status: 'proposed')
      Notifications.publish!(
        event: :settlement_proposed, actor: actor, recipients: [recipient1], resource: order
      )

      n = Notification.last
      expect(n.notification_type).to eq('settlement_proposed')
      expect(n.message).to include('alice proposed a settlement')
      expect(n.target_type).to eq('order')
      expect(n.target_id).to eq(order.id)
      expect(n.recipient).to eq(recipient1)
      expect(n.resolved_at).to be_nil       # actionable: outstanding while 'proposed'
    end

    it 'publishes settlement_completed as a born-resolved FYI to the counterparty' do
      order = Order.create!(user_id: recipient1.id, friend_id: actor.id,
                            order_status: :shipped, settlement_status: 'settled')
      Notifications.publish!(
        event: :settlement_completed, actor: actor, recipients: [recipient1], resource: order
      )

      n = Notification.last
      expect(n.notification_type).to eq('settlement_completed')
      expect(n.message).to include('Settlement complete')
      expect(n.target_type).to eq('order')
      expect(n.recipient).to eq(recipient1)
      expect(n.resolved_at).to be_present
    end

    it 'publishes payment_received as a born-resolved FYI to the payer' do
      trustline = Trustline.create!(
        user_a: actor, user_b: recipient1,
        credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0
      )
      pp = PendingPayment.create!(
        from_user: recipient1, to_user: actor, trustline: trustline,
        amount: 12.5, kind: :payment, status: :confirmed
      )
      Notifications.publish!(
        event: :payment_received, actor: actor, recipients: [recipient1], resource: pp
      )

      n = Notification.last
      expect(n.notification_type).to eq('payment_received')
      expect(n.message).to eq('alice confirmed receipt of your $12.50')
      expect(n.target_type).to eq('trustline')
      expect(n.target_id).to eq(trustline.id)
      expect(n.recipient).to eq(recipient1)
      expect(n.resolved_at).to be_present
    end

    it 'publishes order_shipped as a born-resolved FYI to the buyer' do
      order = Order.create!(user_id: recipient1.id, friend_id: actor.id, order_status: :shipped)
      Notifications.publish!(
        event: :order_shipped, actor: actor, recipients: [recipient1], resource: order
      )

      n = Notification.last
      expect(n.notification_type).to eq('order_shipped')
      expect(n.message).to include('alice shipped')
      expect(n.target_type).to eq('order')
      expect(n.recipient).to eq(recipient1)
      expect(n.resolved_at).to be_present
    end

    it 'publishes order_signed as a born-resolved FYI to the seller' do
      order = Order.create!(user_id: actor.id, friend_id: recipient1.id, order_status: :signed)
      Notifications.publish!(
        event: :order_signed, actor: actor, recipients: [recipient1], resource: order
      )

      n = Notification.last
      expect(n.notification_type).to eq('order_signed')
      expect(n.message).to include('alice signed for')
      expect(n.recipient).to eq(recipient1)
      expect(n.resolved_at).to be_present
    end

    it 'publishes trustline_created as a born-resolved FYI to the counterparty' do
      trustline = Trustline.create!(
        user_a: actor, user_b: recipient1,
        credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0
      )
      Notifications.publish!(
        event: :trustline_created, actor: actor, recipients: [recipient1], resource: trustline
      )

      n = Notification.last
      expect(n.notification_type).to eq('trustline_created')
      expect(n.message).to eq('alice opened a trustline with you')
      expect(n.target_type).to eq('trustline')
      expect(n.target_id).to eq(trustline.id)
      expect(n.recipient).to eq(recipient1)
      expect(n.resolved_at).to be_present
    end

    it 'publishes request_cancelled as a born-resolved FYI to the counterparty' do
      Notifications.publish!(
        event: :request_cancelled, actor: actor, recipients: [recipient1], resource: item_request
      )

      n = Notification.last
      expect(n.notification_type).to eq('request_cancelled')
      expect(n.message).to eq('alice cancelled the request for Tomatoes')
      expect(n.target_type).to eq('item')
      expect(n.recipient).to eq(recipient1)
      expect(n.resolved_at).to be_present
    end
  end

  describe '.resolve!' do
    let(:trustline) do
      Trustline.create!(
        user_a: actor, user_b: recipient1,
        credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0
      )
    end
    let(:pending_payment) do
      PendingPayment.create!(
        from_user: actor, to_user: recipient1, trustline: trustline,
        amount: 25.0, kind: :payment, status: :pending
      )
    end

    def publish_pending_payment!
      Notifications.publish!(
        event:      :pending_payment_created,
        actor:      actor,
        recipients: [recipient1],
        resource:   pending_payment,
        metadata:   {}
      )
    end

    it 'resolves the matching notification once the obligation completes' do
      publish_pending_payment!
      n = Notification.last
      expect(n.resolved_at).to be_nil

      pending_payment.update!(status: :confirmed)
      Notifications.resolve!(pending_payment)

      n.reload
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('confirmed')
    end

    it 'is a no-op when zero matching unresolved notifications exist' do
      expect {
        Notifications.resolve!(pending_payment)
      }.not_to raise_error
      expect(Notification.count).to eq(0)
    end

    it 'creates a born-resolved row when the obligation is already resolved at publish time' do
      pending_payment.update!(status: :confirmed)

      publish_pending_payment!

      n = Notification.last
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('confirmed')
    end

    it 'leaves the row unresolved while resolved_when returns nil' do
      publish_pending_payment!

      Notifications.resolve!(pending_payment)

      n = Notification.last.reload
      expect(n.resolved_at).to be_nil
      expect(n.resolution_reason).to be_nil
    end
  end
end
