class BackfillNotificationSubjectsAndResolution < ActiveRecord::Migration[5.2]
  # One-time data backfill for the actionable-dismissal feature. Links every
  # pre-existing notification row to its obligation object (subject_type /
  # subject_id) and resolves the ones whose obligation is already done, so the
  # new outstanding-count semantics don't count legacy rows forever.
  #
  # SELF-CONTAINED by design: does NOT call Notifications.resolve! or the
  # EventRegistry — the derivation logic is inlined so future registry changes
  # can't alter what this migration did at deploy time.
  #
  # Ships in the same deploy as the unread_count -> outstanding_count change:
  # without this backfill every legacy row (resolved_at NULL) counts toward
  # the badge.
  #
  # No `down`: a backfill of derived data is irreversible by nature, and
  # reversing it would re-inflate every user's badge.
  def up
    backfill_request_created
    backfill_payment_events

    # Log counts for the deploy record.
    # NOTE on where.not semantics: in Rails 5.2 (this app's version)
    # where.not(a: nil, b: nil) is NOR — a IS NOT NULL AND b IS NOT NULL,
    # i.e. exactly the AND we want here. The OR-shaped NAND semantics
    # (NOT (a IS NULL AND b IS NULL)) only arrive in Rails 6.1+. The chained
    # where.not form below is correct under BOTH versions — keep it.
    linked   = Notification.where.not(subject_type: nil).where.not(resolved_at: nil).count
    live     = Notification.where.not(subject_type: nil).where(resolved_at: nil).count
    orphaned = Notification.where(resolution_reason: ['orphaned', 'resolved_elsewhere']).count
    Rails.logger.info("[BackfillNotificationSubjects] linked-live: #{live}, resolved: #{linked}, orphaned/elsewhere: #{orphaned}")
    puts "Backfill complete — live: #{live}, resolved: #{linked}, orphaned/elsewhere: #{orphaned}"
  end

  private

  # --- request_created ---
  # Subject = the ItemRequest hop (one per hop seller).
  # Match via: metadata['request_contract_id'] + friend_id == recipient_id.
  # Status derivation: accepted/completed → :accepted; cancelled → :cancelled;
  # contract nil/cancelled → :cancelled; still pending under live contract → live.
  #
  # IMPORTANT: the column is notification_type, NOT event_type. event_type does
  # not exist; a where(event_type: ...) call raises ActiveRecord::StatementInvalid
  # (Unknown column) at runtime — the backfill would crash mid-run.
  def backfill_request_created
    Notification.where(notification_type: 'request_created', resolved_at: nil).find_each do |n|
      contract_id = n.metadata&.dig('request_contract_id')
      unless contract_id
        n.update_columns(resolved_at: Time.current, resolution_reason: 'orphaned')
        next
      end

      ir = ItemRequest.joins(:request_contract)
                      .where(request_contract_id: contract_id, friend_id: n.recipient_id)
                      .first
      if ir.nil?
        n.update_columns(resolved_at: Time.current, resolution_reason: 'orphaned')
        next
      end

      # Link subject regardless of state
      updates = { subject_type: 'ItemRequest', subject_id: ir.id }

      contract = ir.request_contract
      reason = if ir.accepted? || ir.completed?                  then 'accepted'
               elsif ir.cancelled?                               then 'cancelled'
               elsif contract.nil? || contract.cancelled?        then 'cancelled'
               end

      if reason
        updates.merge!(resolved_at: Time.current, resolution_reason: reason)
      end

      n.update_columns(**updates)
    end
  end

  # --- payment events ---
  # For pending_payment_created, payment_request_created, payment_request_paid:
  # Subject = the PendingPayment. target_id = trustline_id (navigation), not
  # payment_id. Match heuristic: PendingPayments on trustline_id = n.target_id,
  # with the event-specific kind, created_at within n.created_at + 1 minute.
  # Require EXACTLY ONE candidate. Conservative: if ambiguous or none, resolve
  # as resolved_elsewhere. Never guess-link.
  #
  # Verified against app/models/pending_payment.rb:
  #   enum kind:   [:payment, :request]
  #   enum status: [:pending, :confirmed, :rejected, :cancelled, :paid_pending_confirmation]
  #   belongs_to :trustline (column trustline_id)
  def backfill_payment_events
    # `awaiting:` is DOCUMENTATION ONLY — it records who the obligation waits on
    # for each event. Do NOT use it to filter candidates by current status or
    # awaiting-party: already-closed payments must still match so they get
    # linked and resolved below.
    payment_events = {
      'pending_payment_created'  => { kind: 'payment',  awaiting: :payee_confirms },
      'payment_request_created'  => { kind: 'request',  awaiting: :debtor_pays },
      'payment_request_paid'     => { kind: 'request',  awaiting: :creditor_confirms },
    }

    payment_events.each do |event_name, config|
      # Column is notification_type, not event_type — event_type does not exist.
      Notification.where(notification_type: event_name, resolved_at: nil).find_each do |n|
        candidates = PendingPayment
          .where(trustline_id: n.target_id, kind: config[:kind])
          .where('created_at <= ?', n.created_at + 1.minute)
          .order(created_at: :desc)

        if candidates.count != 1
          # Ambiguous or no match — resolve conservatively
          n.update_columns(resolved_at: Time.current, resolution_reason: 'resolved_elsewhere')
          next
        end

        pp = candidates.first

        # Link subject
        updates = { subject_type: 'PendingPayment', subject_id: pp.id }

        # Derive resolution state using the same logic as the registry's resolved_when:
        reason = case event_name
        when 'pending_payment_created'
          if    pp.confirmed? then 'confirmed'
          elsif pp.rejected?  then 'rejected'
          elsif pp.cancelled? then 'cancelled'
          end
        when 'payment_request_created'
          if    pp.paid_pending_confirmation? || pp.confirmed? then 'paid'
          elsif pp.rejected?  then 'rejected'
          elsif pp.cancelled? then 'cancelled'
          end
        when 'payment_request_paid'
          if    pp.confirmed? then 'confirmed'
          elsif pp.rejected?  then 'rejected'
          elsif pp.cancelled? then 'cancelled'
          end
        end

        updates.merge!(resolved_at: Time.current, resolution_reason: reason) if reason
        n.update_columns(**updates)
      end
    end
  end
end
