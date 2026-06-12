require 'rails_helper'
require 'securerandom'

# Domain-hook coverage: the unconditional after_commit hooks on PendingPayment,
# ItemRequest, and RequestContract must resolve outstanding notifications from
# real state transitions. The three multi-save ItemRequest cases (single-hop,
# final-hop, mid-chain) are the cases a `saved_change_to_status?` guard fails
# silently — perform_accept! saves the same row up to three times in one
# transaction, resetting saved-changes tracking.
RSpec.describe 'Notification resolution domain hooks', type: :model, skip_hooks: true do
  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  def create_user(prefix)
    User.create!(user_name: "#{prefix}-#{SecureRandom.hex(3)}", password: 'password123')
  end

  def notification_for(record)
    Notification.find_by(subject_type: record.class.name, subject_id: record.id)
  end

  describe 'PendingPayment transitions' do
    let(:creditor) { create_user('creditor') }
    let(:debtor)   { create_user('debtor') }
    let(:trustline) do
      a, b = [creditor, debtor].sort_by(&:id)
      Trustline.create!(
        user_a: a, user_b: b,
        credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0
      )
    end

    def build_payment(kind:, status: :pending)
      PendingPayment.create!(
        from_user: creditor, to_user: debtor, trustline: trustline,
        amount: 25.0, kind: kind, status: status
      )
    end

    def publish!(event, resource, recipient)
      Notifications.publish!(
        event:      event,
        actor:      resource.from_user == recipient ? resource.to_user : resource.from_user,
        recipients: [recipient],
        resource:   resource,
        metadata:   {}
      )
    end

    it "confirm! resolves the pending_payment_created notification with 'confirmed'" do
      pp = build_payment(kind: :payment)
      publish!(:pending_payment_created, pp, debtor)
      n = notification_for(pp)
      expect(n.resolved_at).to be_nil

      pp.confirm!

      n.reload
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('confirmed')
    end

    it "reject! resolves with 'rejected'" do
      pp = build_payment(kind: :payment)
      publish!(:pending_payment_created, pp, debtor)

      pp.reject!(reason: 'no thanks')

      n = notification_for(pp).reload
      expect(n.resolution_reason).to eq('rejected')
    end

    it "cancel! resolves with 'cancelled'" do
      pp = build_payment(kind: :payment)
      publish!(:pending_payment_created, pp, debtor)

      pp.cancel!

      n = notification_for(pp).reload
      expect(n.resolution_reason).to eq('cancelled')
    end

    it "mark_paid! resolves the payment_request_created notification with 'paid'" do
      pp = build_payment(kind: :request)
      publish!(:payment_request_created, pp, debtor)
      n = notification_for(pp)
      expect(n.resolved_at).to be_nil

      pp.mark_paid!

      n.reload
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('paid')
    end

    it 'edge 4: mark_paid! resolves the debtor notification; the creditor payment_request_paid stays live until confirm!' do
      pp = build_payment(kind: :request)
      publish!(:payment_request_created, pp, debtor)
      debtor_n = notification_for(pp)

      pp.mark_paid!
      expect(debtor_n.reload.resolution_reason).to eq('paid')

      # Debtor has paid; now notify the creditor to confirm receipt.
      Notifications.publish!(
        event:      :payment_request_paid,
        actor:      debtor,
        recipients: [creditor],
        resource:   pp,
        metadata:   {}
      )
      creditor_n = Notification.where(subject_type: 'PendingPayment', subject_id: pp.id)
                               .where(recipient: creditor)
                               .last
      expect(creditor_n.resolved_at).to be_nil

      pp.confirm!

      expect(creditor_n.reload.resolution_reason).to eq('confirmed')
    end
  end

  describe 'ItemRequest transitions' do
    def unit
      ItemUnit.create!(
        unit_name: "pounds-#{SecureRandom.hex(3)}", item_symbol: 'lb',
        unit_type: :weight, equivalent: 453.592
      )
    end

    def build_item(owner, item_unit)
      category = Category.create!(
        category_name: "category-#{SecureRandom.hex(3)}", default_unit: item_unit, kind: :produce
      )
      grade = Grade.create!(name: "A-#{SecureRandom.hex(3)}", value: 30)
      Item.create!(
        user: owner, category: category, grade: grade, item_unit: item_unit,
        name: "Item #{SecureRandom.hex(3)}", price: 5, quantity: 10
      )
    end

    def publish_hop!(hop)
      Notifications.publish!(
        event:      :request_created,
        actor:      hop.user,
        recipients: [hop.friend],
        resource:   hop,
        metadata:   { request_contract_id: hop.request_contract_id }
      )
    end

    # Single-hop: buyer requests directly from the seller (steps: 1, step: 1).
    def build_single_hop
      seller = create_user('seller')
      buyer  = create_user('buyer')
      item   = build_item(seller, unit)
      inventory = item.inventory.first
      contract = RequestContract.create!(
        user: buyer, item: item, inventory_id: inventory.id, quantity: 2, steps: 1
      )
      request = ItemRequest.create!(
        user: buyer, friend: seller, request_contract: contract,
        price: 5, status: :pending, step: 1, sent: true
      )
      { seller: seller, buyer: buyer, request: request, contract: contract }
    end

    # Three-hop chain consumer -> mid1 -> mid2 -> producer. Step numbering and
    # user/friend orientation mirror ItemRequestsController#create: step 1 is
    # the hop whose friend owns the inventory; the consumer's own hop is step 3.
    def build_three_hop_chain
      consumer = create_user('consumer')
      mid1     = create_user('mid1')
      mid2     = create_user('mid2')
      producer = create_user('producer')
      item      = build_item(producer, unit)
      inventory = item.inventory.first
      contract = RequestContract.create!(
        user: consumer, item: item, inventory_id: inventory.id, quantity: 2, steps: 3
      )
      hop3 = ItemRequest.create!(user: consumer, friend: mid1, request_contract: contract,
                                 price: 7, status: :pending, step: 3, sent: true)
      hop2 = ItemRequest.create!(user: mid1, friend: mid2, request_contract: contract,
                                 price: 6, status: :pending, step: 2, sent: false)
      hop1 = ItemRequest.create!(user: mid2, friend: producer, request_contract: contract,
                                 price: 5, status: :pending, step: 1, sent: false)
      [hop1, hop2, hop3].each { |hop| publish_hop!(hop) }
      { contract: contract, hop1: hop1, hop2: hop2, hop3: hop3 }
    end

    it "single-hop accept (step == 1) resolves the seller's request_created notification" do
      data = build_single_hop
      publish_hop!(data[:request])
      n = notification_for(data[:request])
      expect(n.resolved_at).to be_nil

      expect(data[:request].accept_request).to eq(true)

      n.reload
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('accepted')
    end

    it "final-hop accept of a 3-hop chain resolves that hop's notification" do
      chain = build_three_hop_chain

      # Accept hop 1 (inventory owner side), then hop 2, leaving hop 3 last.
      expect(chain[:hop1].accept_request).to eq(true)
      chain[:hop2].update!(status: :reserved)
      expect(chain[:hop2].accept_request).to eq(true)

      final_n = notification_for(chain[:hop3])
      expect(final_n.resolved_at).to be_nil

      chain[:hop3].update!(status: :reserved)
      expect(chain[:hop3].accept_request).to eq(true)

      final_n.reload
      expect(final_n.resolved_at).to be_present
      expect(final_n.resolution_reason).to eq('accepted')
    end

    it "mid-chain accept resolves ONLY that hop's notification" do
      chain = build_three_hop_chain

      expect(chain[:hop2].accept_request).to eq(true)

      expect(notification_for(chain[:hop2]).reload.resolution_reason).to eq('accepted')
      expect(notification_for(chain[:hop1]).reload.resolved_at).to be_nil
      expect(notification_for(chain[:hop3]).reload.resolved_at).to be_nil
    end

    it "contract cancellation resolves all hops' notifications via the contract-level hook" do
      chain = build_three_hop_chain

      # update_callback fans hop statuses with update_all (bypassing ItemRequest
      # callbacks); the RequestContract after_commit hook does the resolving.
      chain[:contract].update!(status: :cancelled)

      [chain[:hop1], chain[:hop2], chain[:hop3]].each do |hop|
        n = notification_for(hop).reload
        expect(n.resolved_at).to be_present
        expect(n.resolution_reason).to eq('cancelled')
      end
    end

    it 'hard-deleting a hop resolves its notification as orphaned' do
      chain = build_three_hop_chain
      hop = chain[:hop2]
      n = notification_for(hop)
      expect(n.resolved_at).to be_nil

      hop.destroy!

      n.reload
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('orphaned')
    end
  end

  describe 'idempotency' do
    it 'a second resolve! is a no-op — first resolution wins' do
      recipient = create_user('recipient')
      n = Notification.create!(
        recipient: recipient, notification_type: 'request_created',
        message: 'someone requested something',
        subject_type: 'ItemRequest', subject_id: 999
      )

      n.resolve!(:accepted)
      n.reload
      first_resolved_at = n.resolved_at

      n.resolve!(:cancelled)
      n.reload

      expect(n.resolved_at).to eq(first_resolved_at)
      expect(n.resolution_reason).to eq('accepted')
    end
  end
end
