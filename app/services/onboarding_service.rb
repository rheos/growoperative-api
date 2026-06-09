class OnboardingService
  # POST /v1/onboarding (Job 11). Consumes an accepted auth invitation
  # and applies Growoperative-specific effects in a single transaction.
  # Idempotent on (invitation_id, foaf_id) per master plan §1.
  #
  # Phase-2 bridge note: today the auth invitation IS the Growoperative
  # invitation (one row), and the User row IS both identity and profile.
  # When auth.foaf.io stands up (Phase 3), this service will receive an
  # already-accepted auth invite and only apply *app* effects to a
  # *separate* GrowoperativeProfile row.

  REJECTION_CODES = %w[
    subnet_full
    banned_email_domain
    role_policy_violation
    abandoned
  ].freeze

  Result = Struct.new(:status, :rejection_code, :invitation, :user, :error_message, keyword_init: true) do
    def completed?
      status == 'completed'
    end

    def rejected?
      status == 'rejected'
    end

    def failed?
      status == 'failed'
    end

    def pending?
      status == 'pending'
    end

    def successful?
      completed?
    end
  end

  class PolicyRejection < StandardError
    attr_reader :code
    def initialize(code, message = nil)
      @code = code
      super(message || code)
    end
  end

  def initialize(user:, invitation_code:, requested_user_type: nil)
    @user = user
    @invitation_code = invitation_code.to_s
    @requested_user_type = requested_user_type
  end

  def call
    invitation = Invitation.find_by_code(@invitation_code)
    return Result.new(status: 'failed', error_message: 'Invitation not found') unless invitation

    # Idempotency: invitation_id + accepted_id (foaf_id stand-in for
    # Phase 2). Returning the existing result keeps retries safe — no
    # duplicate user_groups, relationships, or subnet memberships.
    if invitation.app_onboarding_status == 'completed' && invitation.accepted_id == @user.id
      return Result.new(status: 'completed', invitation: invitation, user: @user)
    end

    # Terminal rejection state must not auto-retry per master plan.
    if invitation.app_onboarding_status == 'rejected'
      return Result.new(
        status: 'rejected',
        rejection_code: invitation.app_onboarding_rejection_code,
        invitation: invitation,
        user: @user,
      )
    end

    # Inviter / accepter sanity — same checks as legacy accept_invitation.
    return reject('role_policy_violation', invitation, 'You can not accept your own invitation.') if invitation.user_id == @user.id
    return reject('role_policy_violation', invitation, 'Demo/non-demo crossover not allowed.') if invitation.user.demo? != @user.demo?

    # Multi-use codes never go terminal (status stays pending, accepted_id
    # stays nil), so the single-use accepted_id/status gates below can never
    # be satisfied. Idempotency keys on whether THIS user already has a
    # redemption row; otherwise apply effects (which records the redemption).
    # The self-redeem / demo-crossover guards above still run first.
    if invitation.multi_use?
      if invitation.invitation_redemptions.exists?(user_id: @user.id)
        return Result.new(status: 'completed', invitation: invitation, user: @user)
      end
      return apply_effects!(invitation)
    end

    # User#after_create callbacks (set_relationship → @invitation.update(status: :accepted, accepted_id: ...))
    # flip legacy `status` to accepted as a side effect of signup. That happens
    # BEFORE the app calls /v1/onboarding, so by the time we get here the
    # invitation is no longer `pending?` even though Job 11's app_onboarding_status
    # column is still 'pending'. The onboarding contract is idempotent on
    # (invitation_code, accepted user) — if accepted_id already points at @user
    # we treat it as a retry and proceed. apply_effects! is idempotent.
    accepted_by_caller = invitation.accepted_id.present? && invitation.accepted_id == @user.id
    return Result.new(status: 'failed', invitation: invitation, error_message: 'Invitation already used') unless invitation.pending? || invitation.app_onboarding_status == 'failed' || accepted_by_caller

    apply_effects!(invitation)
  rescue PolicyRejection => e
    persist_rejection!(invitation, e.code, e.message) if invitation
    Result.new(status: 'rejected', rejection_code: e.code, invitation: invitation, user: @user, error_message: e.message)
  rescue StandardError => e
    # Operational failure — retryable. Capture for status read but do
    # not poison the row with a terminal rejection code.
    invitation&.update_columns(app_onboarding_status: 'failed', updated_at: Time.current)
    Result.new(status: 'failed', invitation: invitation, user: @user, error_message: e.message)
  end

  private

  def apply_effects!(invitation)
    ActiveRecord::Base.transaction do
      enforce_subnet_role_policy!(invitation)

      # Add user_group for invited role (clamped by subnet policy if needed).
      role = effective_role(invitation)
      @user.user_groups.find_or_create_by!(group_label: role) if role.present?

      # Create or no-op the relationship between inviter and invitee.
      ensure_relationship!(invitation)

      # Subnet membership: inherit inviter's primary subnet if invitation
      # doesn't carry one.
      ensure_subnet_membership!(invitation)

      if invitation.multi_use?
        # Multi-use codes stay pending forever; just record this redeemer.
        # find_or_create_by! against the unique index converges with the
        # User after_create callback's write on the same row.
        invitation.invitation_redemptions.find_or_create_by!(user_id: @user.id) do |r|
          r.redeemed_at = Time.current
        end
      else
        invitation.update!(
          status: :accepted,
          accepted_id: @user.id,
          app_onboarding_status: 'completed',
          app_onboarding_completed_at: Time.current,
          app_onboarding_rejection_code: nil,
        )
      end
    end

    Result.new(status: 'completed', invitation: invitation.reload, user: @user.reload)
  end

  # Subnet-level guards: role-policy and email-policy. Master plan
  # rejection codes: role_policy_violation, banned_email_domain.
  # subnet_full and abandoned are reserved for future capacity / 30-day
  # expiry features (not enforced today).
  def enforce_subnet_role_policy!(invitation)
    subnet = invitation.subnet
    return unless subnet

    flags = SiteConfig.for(subnet)

    # Email policy: subnets that require valid email reject onboarders
    # who don't have one. Pre-existing signup-time check; enforced again
    # here for users joining additional networks post-signup.
    if flags[:enforce_valid_email] && @user.email.blank?
      raise PolicyRejection.new('banned_email_domain', 'Subnet requires a valid email.')
    end

    # Role-clamp: when subnet locks role, requested role must match
    # invitation.user_type AND must be in visible_roles.
    visible = Array(flags[:visible_roles]).map(&:to_s)
    requested = (@requested_user_type || invitation.user_type).to_s
    if !flags[:multi_role] && visible.any? && !visible.include?(requested)
      raise PolicyRejection.new('role_policy_violation', "Role #{requested} not allowed in this subnet.")
    end
  end

  def effective_role(invitation)
    subnet = invitation.subnet
    flags = subnet ? SiteConfig.for(subnet) : SiteConfig.defaults
    if !flags[:multi_role]
      Array(flags[:visible_roles]).first.presence || invitation.user_type
    else
      (@requested_user_type || invitation.user_type).to_s
    end
  end

  def ensure_relationship!(invitation)
    inviter_id = invitation.user_id
    accepter_id = @user.id
    existing = Relationship.where(
      '(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)',
      inviter_id, accepter_id, accepter_id, inviter_id,
    ).exists?
    return if existing

    rel = Relationship.new(status: :accepted, action_user_id: inviter_id)
    if accepter_id < inviter_id
      rel.user_id = accepter_id
      rel.friend_id = inviter_id
      rel.user_label = invitation.note_label
      rel.friend_label = invitation.label
    else
      rel.user_id = inviter_id
      rel.friend_id = accepter_id
      rel.user_label = invitation.label
      rel.friend_label = invitation.note_label
    end
    rel.save!
  end

  def ensure_subnet_membership!(invitation)
    subnet = invitation.subnet || invitation.user.primary_subnet
    return unless subnet

    membership = @user.subnet_memberships.find_or_initialize_by(subnet_id: subnet.id)
    if membership.new_record?
      membership.is_primary = !@user.subnet_memberships.where(is_primary: true).exists?
      membership.save!
    end
  end

  def reject(code, invitation, message)
    persist_rejection!(invitation, code, message)
    Result.new(status: 'rejected', rejection_code: code, invitation: invitation, user: @user, error_message: message)
  end

  def persist_rejection!(invitation, code, message)
    return unless invitation
    invitation.update_columns(
      app_onboarding_status: 'rejected',
      app_onboarding_rejection_code: code,
      updated_at: Time.current,
    )
  end
end
