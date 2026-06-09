class Api::V1::RegistrationsController < Api::V1::ApiController
  skip_before_action :authenticate!

  before_action :invitation_limit, :check_chain_limit, :check_subnet_email_policy, only: [:create]

  respond_to :json

  def create
    # Job 42: signup flow now goes through auth.foaf.io for the identity
    # record + token issuance; railsbackend keeps the local users row
    # because the rest of the app (relationships, items, trustlines) is
    # foreign-keyed to users.id. We pre-validate locally, call auth.foaf.io,
    # then link the local row via the returned foaf_id.
    attrs = sign_up_params
    user = User.new(attrs)
    unless user.valid?
      warden.custom_failure!
      return render json: user.errors, status: 422
    end

    # Look up the inviter's foaf_id so auth.foaf.io can create a ContactEdge
    # alongside the new identity. invitation_limit before_action already
    # validated the code resolves; re-look up here to grab the inviter.
    inviter_code = params[:invited_code] || params.dig(:user, :invite_code) || params.dig(:user, :invited_code)
    inviter_foaf_id = Invitation.find_by_code(inviter_code)&.user&.foaf_id

    status, body = AuthFoafClient.signup(
      user_name: user.user_name,
      password: attrs[:password],
      email: user.email.presence,
      first_name: nil,
      last_name: nil,
      display_name: user.name.presence,
      recovery_phrase_acknowledged: user.email.blank?,
      invited_by_foaf_id: inviter_foaf_id
    )

    if status != 201 || body['token'].blank?
      warden.custom_failure!
      Rails.logger.warn("auth.foaf.io signup rejected: status=#{status} error=#{body.is_a?(Hash) ? body['error'] : nil}")
      return render json: { error: (body.is_a?(Hash) && body['error']) || 'Signup failed' }, status: 422
    end

    foaf_id = body.dig('identity', 'foaf_id')
    user.foaf_id = foaf_id if foaf_id.present?
    unless user.save
      # auth.foaf.io minted an identity but the local row failed to save.
      # We orphan the auth identity for now — operator cleanup is fine
      # given the small user volume and the post-validate ordering above
      # makes this race extremely unlikely.
      warden.custom_failure!
      Rails.logger.error("local User.save failed after auth.foaf.io signup created foaf_id=#{foaf_id}: #{user.errors.full_messages}")
      return render json: user.errors, status: 422
    end

    clear_legacy_jwt_cookie!
    render json: UserSerializer.new(user).serializable_hash.merge(
      token: body['token'],
      identity: body['identity']
    ), status: 201
  end

  private

  def sign_up_params
    source = params.require(:user)
    permitted = source.permit(
      :user_name, :password, :password_confirmation, :password_conformation,
      :first_name, :last_name, :name, :email, :invite_code, :invited_code,
    ).to_h
    # The legacy controller permitted :password_conformation (sic) but the
    # User model uses Devise's correctly-spelled :password_confirmation.
    # Normalize the typo back to the correct key.
    if permitted[:password_conformation].present? && permitted[:password_confirmation].blank?
      permitted[:password_confirmation] = permitted[:password_conformation]
    end
    permitted.delete(:password_conformation)
    # invite_code → :invited_code (User column name)
    if permitted[:invite_code].present? && permitted[:invited_code].blank?
      permitted[:invited_code] = permitted[:invite_code]
    end
    permitted.delete(:invite_code)
    # User model has a single :name column — combine first/last if present.
    if permitted[:name].blank? && (permitted[:first_name].present? || permitted[:last_name].present?)
      permitted[:name] = [permitted[:first_name], permitted[:last_name]].compact.reject(&:empty?).join(" ")
    end
    permitted.delete(:first_name)
    permitted.delete(:last_name)
    permitted
  end

  def invitation_limit
    code = params[:invited_code] || params.dig(:user, :invite_code) || params.dig(:user, :invited_code)
    invitation = Invitation.find_by_code(code)

    if invitation.nil?
      return render json: { message: "Invitation code is wrong" }, status: 422
    end

    # Multi-use codes are unlimited until the creator turns them off. They
    # never go "already used" and are exempt from the pending-slot limit —
    # the only failure is being switched off (disabled_at set).
    if invitation.multi_use?
      unless invitation.active?
        render json: { message: "This invitation code is no longer active" }, status: 422
      end
      return
    end

    if invitation.pending?
      unless invitation.user&.ramaining_invitation_limit.to_i >= 0
        render json: { message: "Invitation limit over" }, status: 422
      end
    elsif invitation.accepted?
      render json: { message: "Invitation code is already used" }, status: 422
    else
      render json: { message: "Invitation code is wrong" }, status: 422
    end
  end

  def check_chain_limit
    code = params[:invited_code] || params.dig(:user, :invite_code) || params.dig(:user, :invited_code)
    global_setting = GlobalSetting.find_by(setting: "ChainLimit")
    invited_user = Invitation.find_by_code(code)&.user

    if invited_user.nil?
      return render json: { message: "Invitation code is wrong" }, status: 422
    end

    if global_setting && invited_user.depth >= global_setting.value
      render json: { message: "Chain limit over" }, status: 422
    end
  end

  # Enforces the `enforce_valid_email` subnet flag. When the invitation's
  # subnet requires a valid email, reject signups without one (or with a
  # malformed one). Subnets that don't set the flag accept email-less signups.
  def check_subnet_email_policy
    code = params[:invited_code] || params.dig(:user, :invite_code) || params.dig(:user, :invited_code)
    invitation = Invitation.find_by_code(code)
    subnet = invitation&.subnet
    return unless subnet

    flags = SiteConfig.for(subnet)
    return unless flags[:enforce_valid_email]

    email = params[:email] || params.dig(:user, :email)
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      render json: { message: "A valid email is required to join this subnet" }, status: 422
    end
  end
end
