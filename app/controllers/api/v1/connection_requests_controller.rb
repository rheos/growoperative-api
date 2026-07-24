class Api::V1::ConnectionRequestsController < Api::V1::ApiController

  # GET /v1/connection_requests
  #
  # Lists the current user's PENDING relationship requests, split into:
  #   - incoming: the other party initiated (action_user_id != me.id) → I accept/decline
  #   - outgoing: I initiated (action_user_id == me.id) → shown as "requested"
  #
  # Accepted/declined/blocked rows never appear (excluded by the status = pending WHERE clause).
  # includes(:user, :friend) prevents N+1 on the in-Ruby partition + request_json below.
  def index
    me      = current_user
    pending = Relationship
                .where('user_id = ? OR friend_id = ?', me.id, me.id)
                .where(status: :pending)
                .includes(:user, :friend)

    incoming = pending.select { |r| r.action_user_id != me.id }
    outgoing = pending.select { |r| r.action_user_id == me.id }

    render json: {
      incoming: incoming.map { |r| request_json(r, me) },
      outgoing: outgoing.map { |r| request_json(r, me) }
    }
  end

  # POST /v1/connection_requests  { friend_id: integer }
  #
  # The general connect handshake. Writes an ordinary Relationship(status: :pending) — this
  # is NOT a discovery-specific connection type (the spec forbids that); Local Discovery is
  # simply its first caller.
  #
  # There is NO pair-unique index on the relationships table. The ONLY dup/block guard is the
  # normalization convention (lower id = user_id, higher id = friend_id) plus a MySQL advisory
  # lock keyed on the sorted pair. The lock key is SHARED with introductions
  # (`go:intro:rel:LOW:HIGH`) on purpose: a concurrent introduction-accept and a connect-request
  # on the same pair serialize on the same key, so neither inserts a second row while the other's
  # transaction is still open. Acquire BEFORE the read-check-write transaction; release AFTER it
  # commits, in the `ensure`. Fail closed (503, retryable) if the lock is not acquired.
  def create
    me        = current_user
    friend_id = params[:friend_id].to_i
    friend    = User.find_by(id: friend_id)

    return render json: { message: 'User not found' }, status: :not_found unless friend
    if me.id == friend_id
      return render json: { message: "You can't connect with yourself." }, status: :unprocessable_content
    end

    # Demo boundary pre-check (mirror introductions#create step 7). A demo↔non-demo pair fails
    # the Relationship demo_boundary validation on save!, which would otherwise surface as a raw
    # 500. Pre-check here and return 422 with a clear message so no lock is taken and no row is
    # inserted. (The reuse path below only touches a pre-existing same-demo row, so this covers it.)
    if me.demo? != friend.demo?
      return render json: { message: 'Cannot connect across demo and non-demo accounts' },
                    status: :unprocessable_content
    end

    low_id, high_id = [me.id, friend_id].minmax
    lock_name = "go:intro:rel:#{low_id}:#{high_id}"
    conn = ActiveRecord::Base.connection
    got  = conn.select_value("SELECT GET_LOCK(#{conn.quote(lock_name)}, 5)")
    if got.to_i != 1
      # Timeout (0) or error (NULL) — essentially unreachable since the write is sub-second.
      # Fail closed with a retryable error; the user simply retries.
      return render json: { message: "Couldn't complete right now, please try again." },
                    status: :service_unavailable
    end

    begin
      result      = nil
      was_created = false

      ActiveRecord::Base.transaction do
        existing = Relationship.where(
          '(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)',
          me.id, friend_id, friend_id, me.id
        ).first

        if existing
          if existing.blocked? || existing.accepted? || existing.pending?
            return render json: { message: conflict_message(existing.status.to_sym) },
                          status: :conflict
          end
          # declined → reuse the row in place. There is no pair-unique index, so inserting a
          # second row would create a duplicate; flip the existing declined row back to pending.
          existing.update!(status: :pending, action_user_id: me.id)
          result = existing
        else
          # Normalize: lower user_id = user_id, higher = friend_id.
          rel = Relationship.new(user_id: low_id, friend_id: high_id,
                                 status: :pending, action_user_id: me.id)
          rel.save! # demo_boundary validation (relationship.rb) fires on save
          result      = rel
          was_created = true
        end
      end

      Notifications.publish!(event: :connection_requested, actor: me,
                             recipients: [friend], resource: result)

      # 201 for a freshly-created row; 200 when a prior declined row was reused in place.
      render json: { id: result.id, status: result.status },
             status: (was_created ? :created : :ok)
    ensure
      # Always release — runs after the transaction commits, or on any early return/raise above.
      conn.execute("SELECT RELEASE_LOCK(#{conn.quote(lock_name)})")
    end
  end

  # PATCH /v1/connection_requests/:id/accept
  def accept
    rel = Relationship.find_by(id: params[:id])
    return render json: { message: 'Not found' }, status: :not_found unless rel

    # Must be a party to the relationship.
    unless rel.friend_id == current_user.id || rel.user_id == current_user.id
      return render json: { message: 'Not authorized' }, status: :forbidden
    end
    # The requester (action_user) cannot accept their own request.
    if rel.action_user_id == current_user.id
      return render json: { message: 'Not authorized' }, status: :forbidden
    end
    unless rel.pending?
      return render json: { message: 'This request is no longer pending' }, status: :unprocessable_content
    end

    rel.update!(status: :accepted)

    # Explicitly resolve the recipient's connection_requested obligation row (resolved_when →
    # :accepted). The connection_accepted publish below also resolves it as a side-effect via the
    # shared subject, but resolving here makes the obligation lifecycle explicit and independent of
    # publish ordering (mirrors introductions_controller#accept's Notifications.resolve!).
    Notifications.resolve!(rel)

    # Best-effort FOAF contact edge (same guard+rescue as introductions_controller#accept).
    requester = User.find_by(id: rel.action_user_id)
    begin
      if current_user.foaf_id.present? && requester&.foaf_id.present?
        AuthFoafClient.add_contact_edge(foaf_id_a: current_user.foaf_id,
                                        foaf_id_b: requester.foaf_id)
      end
    rescue StandardError => e
      Rails.logger.warn("connection_requests#accept: FOAF edge failed (non-fatal): #{e.message}")
    end

    Notifications.publish!(event: :connection_accepted, actor: current_user,
                           recipients: [requester].compact, resource: rel)

    render json: { id: rel.id, status: rel.status }
  end

  # PATCH /v1/connection_requests/:id/decline
  def decline
    rel = Relationship.find_by(id: params[:id])
    return render json: { message: 'Not found' }, status: :not_found unless rel
    unless [rel.user_id, rel.friend_id].include?(current_user.id)
      return render json: { message: 'Not authorized' }, status: :forbidden
    end
    unless rel.pending?
      return render json: { message: 'This request is no longer pending' }, status: :unprocessable_content
    end

    rel.update!(status: :declined)

    # Resolve the recipient's connection_requested obligation row (resolved_when → :declined).
    # Decline neither publishes nor resolves otherwise, so without this the actionable
    # "X wants to connect with you" inbox row stays outstanding forever (mirrors
    # introductions_controller#decline's Notifications.resolve!).
    Notifications.resolve!(rel)

    render json: { id: rel.id, status: rel.status }
  end

  # DELETE /v1/connection_requests/:id/withdraw
  #
  # Lets the REQUESTER cancel a pending outgoing request. Mirrors decline but
  # authorizes action_user_id (the sender) rather than either party.
  # Result is identical to decline: status → :declined, recipient notification resolved.
  # A re-send later flips the declined row back to pending (existing create path at :87).
  def withdraw
    rel = Relationship.find_by(id: params[:id])
    return render json: { message: 'Not found' }, status: :not_found unless rel

    # Only the requester may withdraw (action_user_id is who initiated the request).
    unless rel.action_user_id == current_user.id
      return render json: { message: 'Not authorized' }, status: :forbidden
    end

    unless rel.pending?
      return render json: { message: 'This request is no longer pending' }, status: :unprocessable_content
    end

    rel.update!(status: :declined)

    # Resolve the recipient's connection_requested obligation row (resolved_when → :declined).
    # Same as decline: without this, the recipient's "X wants to connect" row stays outstanding.
    Notifications.resolve!(rel)

    render json: { id: rel.id, status: rel.status }
  end

  private

  def conflict_message(status)
    case status
    when :blocked  then 'This connection cannot be made.'
    when :accepted then 'You are already connected.'
    when :pending  then 'A connection request is already pending.'
    end
  end

  # The party on the OTHER side of the relationship from `me` (the normalization convention
  # stores the lower id as user_id, so either side may be me).
  def other_user(rel, me)
    rel.user_id == me.id ? rel.friend : rel.user
  end

  def request_json(rel, me)
    other = other_user(rel, me)
    {
      id:     rel.id,
      status: rel.status,
      user: {
        id:           other.id,
        user_name:    other.user_name,
        display_name: other.display_name.presence,
        avatar_url:   other.avatar_url
      }
    }
  end
end
