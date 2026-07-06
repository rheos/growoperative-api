require 'rails_helper'
require 'securerandom'

# Backend request specs for the general connect handshake (Prompt 10 / Local Discovery Phase 3).
# Covers FR12 / AC9: the endpoints write an ordinary Relationship(status: :pending) and its
# accept/decline transitions. The advisory-lock + normalization convention is the ONLY dup guard
# (no pair-unique index on relationships), so the bidirectional / conflict cases are load-bearing.
#
# skip_hooks: true → no seed load + suite-standard after(:each) truncation, so every
# Relationship/Notification count assertion runs against a clean DB.
RSpec.describe 'Connection Requests API', type: :request, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  before(:each) do
    # accept makes a best-effort AuthFoafClient.add_contact_edge call. Stub it so tests neither
    # hit the network nor depend on the rescue swallowing a connection error.
    allow(AuthFoafClient).to receive(:add_contact_edge).and_return(true)
  end

  # ---- helpers ----------------------------------------------------------------

  def mk(prefix)
    suffix = SecureRandom.hex(4)
    create(:user, user_name: "#{prefix}_#{suffix}", email: "#{prefix}_#{suffix}@test.com")
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{JwtGenerationService.new(user).token}",
      'Content-Type'  => 'application/json' }
  end

  def post_connect(actor, friend_id, headers: nil)
    post '/v1/connection_requests',
         params: { friend_id: friend_id }.to_json,
         headers: headers || auth_headers(actor)
  end

  # Build a Relationship in a given status directly (normalized lower/higher id).
  # action_user defaults to u1. validate:false lets us stage a blocked row across any pair.
  def make_rel(u1, u2, status:, action_user: nil)
    low, high = [u1.id, u2.id].minmax
    rel = Relationship.new(user_id: low, friend_id: high, status: status,
                           action_user_id: (action_user || u1).id)
    rel.save(validate: false)
    rel
  end

  def rel_notifications(rel, type: nil, recipient: nil)
    scope = Notification.where(subject_type: 'Relationship', subject_id: rel.id)
    scope = scope.where(notification_type: type) if type
    scope = scope.where(recipient_id: recipient.id) if recipient
    scope
  end

  # ---- 1. AUTH ----------------------------------------------------------------

  describe 'authentication' do
    it 'POST → 401 unauthenticated' do
      a = mk('a'); b = mk('b')
      post_connect(a, b.id, headers: { 'Content-Type' => 'application/json' })
      expect(response).to have_http_status(:unauthorized)
    end

    it 'PATCH accept → 401 unauthenticated' do
      a = mk('a'); b = mk('b')
      rel = make_rel(a, b, status: :pending, action_user: a)
      patch "/v1/connection_requests/#{rel.id}/accept", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'PATCH decline → 401 unauthenticated' do
      a = mk('a'); b = mk('b')
      rel = make_rel(a, b, status: :pending, action_user: a)
      patch "/v1/connection_requests/#{rel.id}/decline", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ---- 2. POST create ---------------------------------------------------------

  describe 'POST /v1/connection_requests' do
    it 'stranger (no prior relationship) → 201, pending Relationship + connection_requested to the target (AC9)' do
      a = mk('a'); b = mk('b')

      expect { post_connect(a, b.id) }.to change(Relationship, :count).by(1)
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      rel  = Relationship.find(body['id'])
      expect(rel.status).to eq('pending')
      expect(rel.action_user_id).to eq(a.id)
      expect(body['status']).to eq('pending')

      requested = rel_notifications(rel, type: 'connection_requested')
      expect(requested.count).to eq(1)
      expect(requested.first.recipient_id).to eq(b.id)
      expect(requested.first.message).to include(a.user_name)
      # actionable: born outstanding while pending
      expect(requested.first.resolved_at).to be_nil
    end

    it 'normalizes the stored row: user_id = min(me, friend), friend_id = max' do
      u1 = mk('u1'); u2 = mk('u2')
      low, high = [u1.id, u2.id].minmax
      # POST from the HIGHER-id user so normalization is observable (not just insertion order).
      higher = User.find(high)
      lower  = User.find(low)
      post_connect(higher, lower.id)
      expect(response).to have_http_status(:created)

      rel = Relationship.find(JSON.parse(response.body)['id'])
      expect(rel.user_id).to eq(low)
      expect(rel.friend_id).to eq(high)
    end

    it 'already-accepted pair → 409 conflict' do
      a = mk('a'); b = mk('b')
      make_rel(a, b, status: :accepted)

      expect { post_connect(a, b.id) }.not_to change(Relationship, :count)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/already connected/i)
    end

    it 'blocked pair → 409 conflict (requester is either party)' do
      a = mk('a'); b = mk('b')
      make_rel(a, b, status: :blocked, action_user: a)

      # requester = a
      expect { post_connect(a, b.id) }.not_to change(Relationship, :count)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/cannot be made/i)

      # requester = b (other direction of the same normalized row)
      expect { post_connect(b, a.id) }.not_to change(Relationship, :count)
      expect(response).to have_http_status(:conflict)
    end

    it 'existing pending → 409 conflict' do
      a = mk('a'); b = mk('b')
      make_rel(a, b, status: :pending, action_user: a)

      expect { post_connect(a, b.id) }.not_to change(Relationship, :count)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/already pending/i)
    end

    it 'prior declined → 200 reuse (flips to pending in place, no new row inserted)' do
      a = mk('a'); b = mk('b')
      make_rel(a, b, status: :declined, action_user: b)
      expect(Relationship.count).to eq(1)

      expect { post_connect(a, b.id) }.not_to change(Relationship, :count)
      expect(response).to have_http_status(:ok)
      expect(Relationship.count).to eq(1) # reused, not duplicated

      rel = Relationship.first
      expect(rel.status).to eq('pending')
      expect(rel.action_user_id).to eq(a.id)
    end

    it 'self-connect → 422' do
      a = mk('a')
      expect { post_connect(a, a.id) }.not_to change(Relationship, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'unknown friend_id → 404' do
      a = mk('a')
      post_connect(a, 0)
      expect(response).to have_http_status(:not_found)
    end

    it 'bidirectional guard: POST when a row exists in the REVERSE direction also → 409 (lock scenario)' do
      a = mk('a'); b = mk('b')
      # a requests b → normalized pending row
      post_connect(a, b.id)
      expect(response).to have_http_status(:created)
      expect(Relationship.count).to eq(1)

      # b now requests a — the OR-query must find the existing row via the reverse clause.
      expect { post_connect(b, a.id) }.not_to change(Relationship, :count)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['message']).to match(/already pending/i)
    end
  end

  # ---- 3. PATCH accept --------------------------------------------------------

  describe 'PATCH /v1/connection_requests/:id/accept' do
    it 'target accepts → 200, status accepted, connection_accepted notice to the requester' do
      a = mk('a'); b = mk('b')
      post_connect(a, b.id)
      rel = Relationship.find(JSON.parse(response.body)['id'])

      patch "/v1/connection_requests/#{rel.id}/accept", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('accepted')
      expect(rel.reload.status).to eq('accepted')

      accepted = rel_notifications(rel, type: 'connection_accepted')
      expect(accepted.count).to eq(1)
      expect(accepted.first.recipient_id).to eq(a.id)
      expect(accepted.first.message).to include(b.user_name)
    end

    it 'requester cannot accept their own request → 403' do
      a = mk('a'); b = mk('b')
      post_connect(a, b.id)
      rel = Relationship.find(JSON.parse(response.body)['id'])

      patch "/v1/connection_requests/#{rel.id}/accept", headers: auth_headers(a)
      expect(response).to have_http_status(:forbidden)
      expect(rel.reload.status).to eq('pending')
    end

    it 'non-party cannot accept → 403' do
      a = mk('a'); b = mk('b'); outsider = mk('out')
      post_connect(a, b.id)
      rel = Relationship.find(JSON.parse(response.body)['id'])

      patch "/v1/connection_requests/#{rel.id}/accept", headers: auth_headers(outsider)
      expect(response).to have_http_status(:forbidden)
    end

    it 'accept a non-pending request → 422' do
      a = mk('a'); b = mk('b')
      rel = make_rel(a, b, status: :accepted, action_user: a)

      patch "/v1/connection_requests/#{rel.id}/accept", headers: auth_headers(b)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'accept a missing id → 404' do
      a = mk('a')
      patch '/v1/connection_requests/0/accept', headers: auth_headers(a)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---- 4. PATCH decline -------------------------------------------------------

  describe 'PATCH /v1/connection_requests/:id/decline' do
    it 'target declines → 200, status declined' do
      a = mk('a'); b = mk('b')
      post_connect(a, b.id)
      rel = Relationship.find(JSON.parse(response.body)['id'])

      patch "/v1/connection_requests/#{rel.id}/decline", headers: auth_headers(b)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('declined')
      expect(rel.reload.status).to eq('declined')
    end

    it 'non-party cannot decline → 403' do
      a = mk('a'); b = mk('b'); outsider = mk('out')
      post_connect(a, b.id)
      rel = Relationship.find(JSON.parse(response.body)['id'])

      patch "/v1/connection_requests/#{rel.id}/decline", headers: auth_headers(outsider)
      expect(response).to have_http_status(:forbidden)
    end

    it 'decline a non-pending request → 422' do
      a = mk('a'); b = mk('b')
      rel = make_rel(a, b, status: :accepted, action_user: a)

      patch "/v1/connection_requests/#{rel.id}/decline", headers: auth_headers(b)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---- 5. EDGE 5 (spec:93) — target opts out of discovery mid-session ---------

  describe 'discovery opt-out does not affect the connect write (Edge 5)' do
    it 'POST connect still succeeds when the target has location_opted_in = false' do
      a = mk('a'); b = mk('b')
      b.update_column(:location_opted_in, false)

      expect { post_connect(a, b.id) }.to change(Relationship, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(Relationship.find(JSON.parse(response.body)['id']).status).to eq('pending')
    end
  end
end
