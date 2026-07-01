require 'rails_helper'
require 'securerandom'

# Backend request specs for the Contact Introductions lifecycle.
# Covers AC1–AC10 the backend owns, plus the resolver-regression that proves
# the resolver.rb `notification:` kwarg addition did not break the four shipped
# events (which all use ->(subject:, **)).
#
# skip_hooks: true → no seed load + the suite-standard after(:each) truncation,
# so every notification/relationship count assertion runs against a clean DB.
RSpec.describe 'Introductions API', type: :request, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  before(:each) do
    # The completion path makes a best-effort AuthFoafClient.add_contact_edge call.
    # Stub it so tests neither hit the network nor depend on the rescue swallowing
    # a connection error.
    allow(AuthFoafClient).to receive(:add_contact_edge).and_return(true)
  end

  # ---- helpers ----------------------------------------------------------------

  def mk(prefix)
    suffix = SecureRandom.hex(4)
    create(:user, user_name: "#{prefix}_#{suffix}", email: "#{prefix}_#{suffix}@test.com")
  end

  def mk_demo(prefix)
    u = mk(prefix)
    create(:user_group, user: u, group_label: 'demo')
    u
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{JwtGenerationService.new(user).token}",
      'Content-Type'  => 'application/json' }
  end

  # Accepted Relationship between two users (normalized lower/higher id).
  def connect!(u1, u2)
    low, high = [u1.id, u2.id].minmax
    Relationship.create!(user_id: low, friend_id: high, status: :accepted, action_user_id: u1.id)
  end

  # Accepted Relationship bypassing the demo_boundary validation (AC10 setup).
  def force_connect!(u1, u2)
    low, high = [u1.id, u2.id].minmax
    rel = Relationship.new(user_id: low, friend_id: high, status: :accepted, action_user_id: u1.id)
    rel.save(validate: false)
    rel
  end

  def post_intro(a, b_id, c_id)
    post '/v1/introductions',
         params: { introducee_a_user_id: b_id, introducee_b_user_id: c_id }.to_json,
         headers: auth_headers(a)
  end

  # Create a pending introduction A→(B,C) via the API and return the record.
  def create_pending_intro(a, b, c)
    post_intro(a, b.id, c.id)
    expect(response).to have_http_status(:created)
    Introduction.find(JSON.parse(response.body)['id'])
  end

  def intro_notifications(intro, type: nil, recipient: nil)
    scope = Notification.where(subject_type: 'Introduction', subject_id: intro.id)
    scope = scope.where(notification_type: type) if type
    scope = scope.where(recipient_id: recipient.id) if recipient
    scope
  end

  # ---- 1. VALIDATION (create) -------------------------------------------------

  describe 'POST /v1/introductions — validation' do
    it 'rejects an unauthenticated request' do
      b = mk('b'); c = mk('c')
      post '/v1/introductions',
           params: { introducee_a_user_id: b.id, introducee_b_user_id: c.id }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'self-introduction (B == C) → 409' do
      a = mk('a'); b = mk('b')
      connect!(a, b)
      post_intro(a, b.id, b.id)
      expect(response).to have_http_status(:conflict)
      expect(intro_notifications_count).to eq(0)
    end

    it 'self-introduction (A == B) → 409' do
      a = mk('a'); c = mk('c')
      connect!(a, c)
      post_intro(a, a.id, c.id)
      expect(response).to have_http_status(:conflict)
    end

    it 'B not an accepted contact of A → 409' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, c) # only A–C connected
      post_intro(a, b.id, c.id)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/not in your contacts/i)
    end

    it 'C not an accepted contact of A → 409' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b) # only A–B connected
      post_intro(a, b.id, c.id)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/not in your contacts/i)
    end

    it 'B and C already connected → 409 "already connected" (AC3)' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c); connect!(b, c)
      post_intro(a, b.id, c.id)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/already connected/i)
    end

    it 'B and C have a BLOCKED relationship → 409, no introduction, no notifications (W2 create guard)' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      # Force-create a blocked B↔C Relationship (same save(validate: false) technique as the
      # AC10 cross-demo test). A block must never be un-blocked by an introduction.
      low, high = [b.id, c.id].minmax
      blocked = Relationship.new(user_id: low, friend_id: high, status: :blocked, action_user_id: b.id)
      blocked.save(validate: false)

      expect { post_intro(a, b.id, c.id) }.not_to change(Introduction, :count)
      expect(response).to have_http_status(:conflict)
      expect(Notification.where(subject_type: 'Introduction').count).to eq(0)
    end

    it 'duplicate pending introduction (both B/C orderings) → 409 (AC4)' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      create_pending_intro(a, b, c)

      # same ordering
      post_intro(a, b.id, c.id)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/pending introduction/i)

      # swapped ordering — the dup check is on the unordered {B,C} pair
      post_intro(a, c.id, b.id)
      expect(response).to have_http_status(:conflict)
    end

    it 'valid create → 201 with a pending Introduction + two requested notifications' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)

      expect { post_intro(a, b.id, c.id) }.to change(Introduction, :count).by(1)
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      intro = Introduction.find(body['id'])
      expect(intro.status).to eq('pending')
      expect(intro.introducer_id).to eq(a.id)
      expect(intro.introducee_a_id).to eq(b.id)
      expect(intro.introducee_b_id).to eq(c.id)

      requested = intro_notifications(intro, type: 'introduction_requested')
      expect(requested.count).to eq(2)
      # each row names the OTHER introducee
      expect(requested.find_by(recipient_id: b.id).message).to include(c.user_name)
      expect(requested.find_by(recipient_id: c.id).message).to include(b.user_name)
    end
  end

  # ---- 2. DEMO BOUNDARY (AC10) ------------------------------------------------

  describe 'POST /v1/introductions — demo boundary (AC10)' do
    it 'cross-demo triple reaches demo_consistent? → 422 with zero notifications' do
      a = mk_demo('demo_a')        # demo
      b = mk('plain_b')            # non-demo
      c = mk('plain_c')            # non-demo
      # Force cross-demo accepted relationships (bypass demo_boundary) so the
      # contact + dup checks pass and the request reaches demo_consistent?.
      force_connect!(a, b)
      force_connect!(a, c)

      expect { post_intro(a, b.id, c.id) }.not_to change(Introduction, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Notification.where(subject_type: 'Introduction').count).to eq(0)
    end
  end

  # ---- 3. SHOW ----------------------------------------------------------------

  describe 'GET /v1/introductions/:id' do
    it 'non-party → 404 (does not leak existence)' do
      a = mk('a'); b = mk('b'); c = mk('c'); outsider = mk('out')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      get "/v1/introductions/#{intro.id}", headers: auth_headers(outsider)
      expect(response).to have_http_status(:not_found)
    end

    it 'party → 200 with the documented JSON shape' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      get "/v1/introductions/#{intro.id}", headers: auth_headers(a)
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body['id']).to eq(intro.id)
      expect(body['status']).to eq('pending')
      expect(body['declined_by_id']).to be_nil
      %w[introducer introducee_a introducee_b].each do |key|
        expect(body[key].keys).to match_array(%w[id name avatar_url])
      end
      expect(body['introducer']['id']).to eq(a.id)
      expect(body['introducer']['name']).to eq(a.user_name)
      expect(body['viewer']).to eq('is_party' => true, 'has_acted' => false, 'can_act' => false)
    end
  end

  # ---- 4. ACCEPT — half-accept ------------------------------------------------

  describe 'PATCH /v1/introductions/:id/accept — half-accept' do
    it 'non-party → 403 (AC5)' do
      a = mk('a'); b = mk('b'); c = mk('c'); outsider = mk('out')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(outsider)
      expect(response).to have_http_status(:forbidden)
    end

    it 'introducer cannot accept → 403' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(a)
      expect(response).to have_http_status(:forbidden)
    end

    it "B accepts: accepted_a_at set, still pending, B's row resolves 'accepted', C's stays outstanding (AC1)" do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)

      intro.reload
      expect(intro.accepted_a_at).to be_present
      expect(intro.status).to eq('pending')

      b_row = intro_notifications(intro, type: 'introduction_requested', recipient: b).first.reload
      expect(b_row.resolved_at).to be_present
      expect(b_row.resolution_reason).to eq('accepted')

      c_row = intro_notifications(intro, type: 'introduction_requested', recipient: c).first.reload
      expect(c_row.resolved_at).to be_nil
    end

    it 'second accept from B → 422 (FR14)' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---- 5. ACCEPT — both accept → completion (AC6, AC9) ------------------------

  describe 'PATCH /v1/introductions/:id/accept — completion' do
    it 'both accept → completed, one accepted Relationship, both requested rows resolved, three completed rows born resolved' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)
      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(c)
      expect(response).to have_http_status(:ok)

      expect(intro.reload.status).to eq('completed')

      # AC6 — exactly one accepted Relationship between B and C, action_user = A
      low, high = [b.id, c.id].minmax
      rels = Relationship.where(user_id: low, friend_id: high)
      expect(rels.count).to eq(1)
      rel = rels.first
      expect(rel.status).to eq('accepted')
      expect(rel.action_user_id).to eq(a.id)

      # FR12 — both introduction_requested rows resolved
      requested = intro_notifications(intro, type: 'introduction_requested')
      expect(requested.count).to eq(2)
      expect(requested.where(resolved_at: nil).count).to eq(0)

      # AC9 — exactly three introduction_completed rows, one per party, born resolved
      completed = intro_notifications(intro, type: 'introduction_completed')
      expect(completed.count).to eq(3)
      expect(completed.pluck(:recipient_id)).to match_array([a.id, b.id, c.id])
      completed.each do |row|
        expect(row.resolved_at).to be_present
        expect(row.resolution_reason).to eq('informational')
      end
      # actors are non-self: B's row has actor C, C's row has actor B, A's row has actor B (introducee_a)
      expect(completed.find_by(recipient_id: b.id).actor_id).to eq(c.id)
      expect(completed.find_by(recipient_id: c.id).actor_id).to eq(b.id)
      expect(completed.find_by(recipient_id: a.id).actor_id).to eq(b.id)
    end

    it 'completes correctly with the W1 pair advisory lock in place and releases it (no leaked lock)' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(c)
      expect(response).to have_http_status(:ok)
      expect(intro.reload.status).to eq('completed')

      # The GET_LOCK / RELEASE_LOCK wrapping did not break the normal completion path:
      # still exactly one accepted Relationship (AC6).
      low, high = [b.id, c.id].minmax
      rels = Relationship.where(user_id: low, friend_id: high)
      expect(rels.count).to eq(1)
      expect(rels.first.status).to eq('accepted')

      # And the pair advisory lock was released after the completion transaction committed —
      # a leaked (never-released) lock would still be held by this session, so IS_FREE_LOCK == 0.
      # (Request specs run in-process on the same connection/session, so this session is the one
      # that acquired the lock.) IS_FREE_LOCK returns 1 when the named lock is free.
      lock_name = "go:intro:rel:#{low}:#{high}"
      free = ActiveRecord::Base.connection.select_value(
        "SELECT IS_FREE_LOCK(#{ActiveRecord::Base.connection.quote(lock_name)})"
      )
      expect(free.to_i).to eq(1)
    end

    it 'no-revert: a completed introduction cannot be declined → 422, stays completed (AC2)' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(c)
      expect(intro.reload.status).to eq('completed')

      patch "/v1/introductions/#{intro.id}/decline", headers: auth_headers(b)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(intro.reload.status).to eq('completed')
    end
  end

  # ---- 6. DECLINE (AC7, AC8) --------------------------------------------------

  describe 'PATCH /v1/introductions/:id/decline' do
    it "B declines → declined, both requested rows resolve 'declined', C can no longer act, A gets one declined notice naming B" do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/decline", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)

      intro.reload
      expect(intro.status).to eq('declined')
      expect(intro.declined_by_id).to eq(b.id)

      # AC7 — both requested rows resolved with reason 'declined'
      requested = intro_notifications(intro, type: 'introduction_requested')
      expect(requested.count).to eq(2)
      requested.each do |row|
        expect(row.reload.resolution_reason).to eq('declined')
      end

      # AC7 — C can no longer accept or decline (no longer pending)
      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(c)
      expect(response).to have_http_status(:unprocessable_entity)
      patch "/v1/introductions/#{intro.id}/decline", headers: auth_headers(c)
      expect(response).to have_http_status(:unprocessable_entity)

      # AC8 — A gets exactly one introduction_declined notice whose message names B
      declined = intro_notifications(intro, type: 'introduction_declined', recipient: a)
      expect(declined.count).to eq(1)
      expect(declined.first.message).to include(b.user_name)
    end
  end

  # ---- 7. RESOLVER REGRESSION (existing events still resolve) -----------------

  describe 'resolver regression — shipped events still resolve after the notification: kwarg' do
    def build_item_unit
      ItemUnit.create!(unit_name: "pounds-#{SecureRandom.hex(3)}", item_symbol: 'lb',
                       unit_type: :weight, equivalent: 453.592)
    end

    def build_item(owner)
      iu       = build_item_unit
      category = Category.create!(category_name: "cat-#{SecureRandom.hex(3)}", default_unit: iu, kind: :produce)
      grade    = Grade.create!(name: "A-#{SecureRandom.hex(3)}", value: 30)
      Item.create!(user: owner, category: category, grade: grade, item_unit: iu,
                   name: "Item #{SecureRandom.hex(3)}", price: 5, quantity: 10)
    end

    it "resolves a request_created notification as 'accepted' when its ItemRequest is accepted" do
      buyer  = mk('rqbuyer')
      seller = mk('rqseller')
      item      = build_item(seller)
      inventory = item.inventory.first
      contract  = RequestContract.create!(user: buyer, item: item, inventory_id: inventory.id, quantity: 2, steps: 1)
      request   = ItemRequest.create!(user: buyer, friend: seller, request_contract: contract,
                                      price: 5, status: :pending, step: 1, sent: true)

      Notifications.publish!(event: :request_created, actor: buyer, recipients: [seller],
                             resource: request, metadata: { request_contract_id: contract.id })

      n = Notification.find_by(subject_type: 'ItemRequest', subject_id: request.id)
      expect(n).to be_present
      expect(n.resolved_at).to be_nil

      # Set accepted WITHOUT firing the model callback, so the explicit resolve!
      # below is what exercises the resolved_when path (and the new kwarg).
      request.update_column(:status, ItemRequest.statuses[:accepted])
      Notifications.resolve!(request)

      n.reload
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('accepted')
    end

    it "resolves a pending_payment_created notification as 'confirmed' when its PendingPayment is confirmed" do
      creditor = mk('ppcreditor')
      debtor   = mk('ppdebtor')
      ua, ub   = [creditor, debtor].sort_by(&:id)
      trustline = Trustline.create!(user_a: ua, user_b: ub,
                                    credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0)
      payment = PendingPayment.create!(from_user: creditor, to_user: debtor, trustline: trustline,
                                       amount: 25.0, kind: :payment, status: :pending)

      Notifications.publish!(event: :pending_payment_created, actor: creditor, recipients: [debtor],
                             resource: payment, metadata: {})

      n = Notification.find_by(subject_type: 'PendingPayment', subject_id: payment.id)
      expect(n).to be_present
      expect(n.resolved_at).to be_nil

      # Set confirmed WITHOUT firing the model callback, so the explicit resolve!
      # below is what exercises the resolved_when path (and the new notification: kwarg).
      payment.update_column(:status, PendingPayment.statuses[:confirmed])
      Notifications.resolve!(payment)

      n.reload
      expect(n.resolved_at).to be_present
      expect(n.resolution_reason).to eq('confirmed')
    end
  end

  # ---- 8. CONCURRENT-ACCEPT (Edge 2 — exactly one Relationship) ---------------

  describe 'PATCH accept — concurrent / re-entrant completion (Edge 2)' do
    it 'a second completing accept does not create a duplicate Relationship' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(c)
      expect(intro.reload.status).to eq('completed')

      low, high = [b.id, c.id].minmax
      expect(Relationship.where(user_id: low, friend_id: high).count).to eq(1)

      # Simulate the race: reset to pending with B's acceptance unset (as a concurrent
      # thread would have seen it) while C's acceptance and the Relationship persist.
      intro.update_columns(status: Introduction.statuses[:pending], accepted_a_at: nil)

      patch "/v1/introductions/#{intro.id}/accept", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)
      expect(intro.reload.status).to eq('completed')

      # find_or_create_by! returned the existing row — still exactly one Relationship.
      expect(Relationship.where(user_id: low, friend_id: high).count).to eq(1)
    end
  end

  # ---- 9. RE-INTRODUCE AFTER DECLINE (Edge 5) ---------------------------------

  describe 'POST /v1/introductions — re-introduce after decline (Edge 5)' do
    it 'the same A/B/C triple can be re-posted after a decline → 201' do
      a = mk('a'); b = mk('b'); c = mk('c')
      connect!(a, b); connect!(a, c)
      intro = create_pending_intro(a, b, c)

      patch "/v1/introductions/#{intro.id}/decline", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)

      # dup-pending check only blocks :pending introductions; a declined one does not.
      expect { post_intro(a, b.id, c.id) }.to change(Introduction, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end

  # ---- shared count helper used by a couple of validation examples ------------

  def intro_notifications_count
    Notification.where(subject_type: 'Introduction').count
  end
end
