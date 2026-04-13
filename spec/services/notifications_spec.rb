require 'rails_helper'

RSpec.describe Notifications, type: :model, skip_hooks: true do
  let(:actor)      { User.create!(user_name: 'alice', password: 'password123') }
  let(:recipient1) { User.create!(user_name: 'bob',   password: 'password123') }
  let(:recipient2) { User.create!(user_name: 'carol', password: 'password123') }

  # Minimal object graph for request_created event
  let(:grade)    { Grade.create!(name: 'A', value: 30) }
  let(:category) { Category.create!(category_name: 'greens', default_unit: 1, default_consumer_unit: 1, default_node_price: 1.0) }
  let(:item_unit) { ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lbs') }
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
  end
end
