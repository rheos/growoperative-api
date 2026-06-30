class Api::V1::IntroductionsController < Api::V1::ApiController

  def create
    a = current_user
    b_id = params[:introducee_a_user_id].to_i
    c_id = params[:introducee_b_user_id].to_i
    b = User.find_by(id: b_id)
    c = User.find_by(id: c_id)

    return render json: { message: 'User not found' }, status: :not_found unless b && c

    # VALIDATION ORDER (each returns before any notification row is created)

    # 1. Self-introduction guard (B=C, A=B, A=C)
    if b_id == c_id || a.id == b_id || a.id == c_id
      return render json: { message: 'Invalid introduction' }, status: :conflict
    end

    # 2. B must be A's accepted contact (either direction)
    unless accepted_contact?(a, b)
      return render json: { message: 'Introducee is not in your contacts' }, status: :conflict
    end

    # 3. C must be A's accepted contact (either direction)
    unless accepted_contact?(a, c)
      return render json: { message: 'Introducee is not in your contacts' }, status: :conflict
    end

    # 4. B and C must not already have an accepted relationship
    if accepted_contact?(b, c)
      return render json: { message: 'These contacts are already connected' }, status: :conflict
    end

    # 5. B and C must not have a BLOCKED relationship (either direction). A block is
    #    sacrosanct: an introduction must never un-block a pair one party deliberately
    #    blocked (W2 safety guard). The message is intentionally generic so it does not
    #    leak who blocked whom.
    if blocked_pair?(b, c)
      return render json: { message: "These contacts can't be introduced." }, status: :conflict
    end

    # 6. No pending introduction for this A/{B,C} triple (unordered B/C pair)
    if Introduction.where(introducer_id: a.id, status: :pending)
                   .where('(introducee_a_id = :b AND introducee_b_id = :c) OR (introducee_a_id = :c AND introducee_b_id = :b)', b: b_id, c: c_id)
                   .exists?
      return render json: { message: 'A pending introduction for this pair already exists' }, status: :conflict
    end

    # 7. Demo boundary (belt-and-suspenders; structurally unreachable via the public API
    #    because the accepted-contact checks above already force same-demo, but kept as
    #    cheap defense-in-depth per Architecture → Technical Risks → demo-422)
    intro_check = Introduction.new(introducer: a, introducee_a: b, introducee_b: c)
    unless intro_check.demo_consistent?
      return render json: { message: 'Cannot introduce across demo and non-demo accounts' }, status: :unprocessable_entity
    end

    # Create introduction and publish notifications to B and C
    introduction = Introduction.create!(introducer: a, introducee_a: b, introducee_b: c, status: :pending)

    # Two separate publish! calls — one per recipient — because the message must name
    # the OTHER introducee, which differs per recipient (publisher.rb:25 evaluates message
    # once per call, shared across all recipients in that call)
    Notifications.publish!(
      event:      :introduction_requested,
      actor:      a,
      recipients: [b],
      resource:   introduction,
      metadata:   { other_introducee_name: c.user_name, other_introducee_id: c.id }
    )
    Notifications.publish!(
      event:      :introduction_requested,
      actor:      a,
      recipients: [c],
      resource:   introduction,
      metadata:   { other_introducee_name: b.user_name, other_introducee_id: b.id }
    )

    render json: introduction_json(introduction), status: :created
  end

  def show
    introduction = Introduction.find_by(id: params[:id])
    return render json: { message: 'Not found' }, status: :not_found unless introduction
    return render json: { message: 'Not found' }, status: :not_found unless introduction.party?(current_user.id)
    render json: introduction_json(introduction)
  end

  def accept
    introduction = Introduction.find_by(id: params[:id])
    return render json: { message: 'Not found' }, status: :not_found unless introduction

    unless introduction.party?(current_user.id) &&
           (current_user.id == introduction.introducee_a_id || current_user.id == introduction.introducee_b_id)
      return render json: { message: 'Not authorized' }, status: :forbidden
    end

    unless introduction.pending?
      return render json: { message: 'This introduction is no longer pending' }, status: :unprocessable_entity
    end

    if introduction.accepted_by?(current_user.id)
      return render json: { message: 'You have already responded to this introduction' }, status: :unprocessable_entity
    end

    did_complete = false

    introduction.with_lock do
      # Re-check status inside the lock (concurrent accept race)
      unless introduction.pending?
        return render json: { message: 'This introduction is no longer pending' }, status: :unprocessable_entity
      end

      introduction.accept_for!(current_user.id)

      if introduction.both_accepted?
        b = introduction.introducee_a
        c = introduction.introducee_b

        # find_or_create_by! (BANG) on the normalized lower/higher-ID pair — serialized by the
        # row lock. The bang raises if the record fails to persist (validation error), rolling back
        # the transaction and leaving status as :pending — AC6: "exactly one Relationship".
        # If a prior Relationship already exists between B and C, find_or_create_by! matches on
        # (user_id, friend_id) and returns that row as-is (its status is ignored by the match), so
        # we may need to upgrade it.
        low_id, high_id = [b.id, c.id].minmax
        rel = Relationship.find_or_create_by!(user_id: low_id, friend_id: high_id) do |r|
          r.status = :accepted
          r.action_user_id = introduction.introducer_id
        end
        # Upgrade a prior :pending OR :declined row to :accepted — both B and C have now explicitly
        # consented to this introduction, so promoting a prior unaccepted/declined request is correct
        # (consistent with Edge 5 re-introduction). A :blocked row is left UNTOUCHED: a block is
        # sacrosanct and must never be flipped by an introduction. The create guard (#5) already
        # rejects blocked pairs, so `|| rel.blocked?` is the TOCTOU backstop for a block that lands
        # between create and accept.
        rel.update!(status: :accepted, action_user_id: introduction.introducer_id) unless rel.accepted? || rel.blocked?

        introduction.update!(status: :completed)
        did_complete = true
      end
    end

    # --- After the lock block commits (no row lock held across network calls) ---

    Notifications.resolve!(introduction)

    if did_complete
      b = introduction.introducee_a
      c = introduction.introducee_b
      a = introduction.introducer

      # Best-effort FOAF contact graph update (same guard+rescue as users_controller.rb:333-342)
      begin
        if b.foaf_id.present? && c.foaf_id.present?
          AuthFoafClient.add_contact_edge(foaf_id_a: b.foaf_id, foaf_id_b: c.foaf_id)
        end
      rescue StandardError => e
        Rails.logger.warn("introductions#accept: FOAF contact_edge upsert failed (non-fatal): #{e.message}")
      end

      # THREE separate publish! calls — one per party, each with a NON-SELF actor —
      # because publisher.rb:36 skips recipient == actor. A single publish with all three
      # recipients and any one actor would silently drop that actor's own row (AC9 failure).
      Notifications.publish!(
        event:      :introduction_completed,
        actor:      c,                        # NOT b (b is the recipient)
        recipients: [b],
        resource:   introduction,
        metadata:   { other_introducee_name: c.user_name }
      )
      Notifications.publish!(
        event:      :introduction_completed,
        actor:      b,                        # NOT c
        recipients: [c],
        resource:   introduction,
        metadata:   { other_introducee_name: b.user_name }
      )
      Notifications.publish!(
        event:      :introduction_completed,
        actor:      introduction.introducee_a, # deterministically non-A: introducee_a is never A
        recipients: [a],
        resource:   introduction,
        metadata:   { introducee_a_name: b.user_name, introducee_b_name: c.user_name }
      )
    end

    render json: introduction_json(introduction)
  end

  def decline
    introduction = Introduction.find_by(id: params[:id])
    return render json: { message: 'Not found' }, status: :not_found unless introduction

    unless introduction.party?(current_user.id) &&
           (current_user.id == introduction.introducee_a_id || current_user.id == introduction.introducee_b_id)
      return render json: { message: 'Not authorized' }, status: :forbidden
    end

    unless introduction.pending?
      return render json: { message: 'This introduction is no longer pending' }, status: :unprocessable_entity
    end

    introduction.update!(status: :declined, declined_by_id: current_user.id)

    # Resolve both B's and C's introduction_requested notification rows (both resolve as :declined)
    Notifications.resolve!(introduction)

    # Notify A — actor is the decliner so the message lambda reads actor.user_name correctly
    Notifications.publish!(
      event:      :introduction_declined,
      actor:      current_user,
      recipients: [introduction.introducer],
      resource:   introduction,
      metadata:   {}
    )

    render json: introduction_json(introduction)
  end

  private

  # Returns true when there is an accepted Relationship between user_a and user_b in either direction.
  def accepted_contact?(user_a, user_b)
    Relationship.where(status: :accepted)
                .where('(user_id = :a AND friend_id = :b) OR (user_id = :b AND friend_id = :a)',
                       a: user_a.id, b: user_b.id)
                .exists?
  end

  # Returns true when there is a blocked Relationship between user_a and user_b in either direction.
  def blocked_pair?(user_a, user_b)
    Relationship.where(status: :blocked)
                .where('(user_id = :a AND friend_id = :b) OR (user_id = :b AND friend_id = :a)',
                       a: user_a.id, b: user_b.id)
                .exists?
  end

  def introduction_json(intro)
    viewer = current_user
    is_party = intro.party?(viewer.id)
    has_acted = is_party && (viewer.id == intro.introducer_id ? false : intro.accepted_by?(viewer.id))
    can_act = intro.pending? && is_party && !has_acted &&
              (viewer.id == intro.introducee_a_id || viewer.id == intro.introducee_b_id)

    {
      id:           intro.id,
      status:       intro.status,
      introducer:   user_stub(intro.introducer),
      introducee_a: user_stub(intro.introducee_a),
      introducee_b: user_stub(intro.introducee_b),
      declined_by_id: intro.declined_by_id,
      viewer: {
        is_party:  is_party,
        has_acted: has_acted,
        can_act:   can_act
      }
    }
  end

  def user_stub(user)
    { id: user.id, name: user.user_name, avatar_url: user.avatar_url }
  end
end
