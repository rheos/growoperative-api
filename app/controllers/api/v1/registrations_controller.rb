class Api::V1::RegistrationsController < Api::V1::ApiController
  skip_before_action :authenticate!

  before_action :invitation_limit, :check_chain_limit, :check_subnet_email_policy, only: [:create]

  respond_to :json

  def create
    user = User.new(sign_up_params)
    if user.save
      clear_legacy_jwt_cookie!
      token = JwtGenerationService.new(user).token
      render json: UserSerializer.new(user).serializable_hash.merge(
        token: token,
        identity: identity_payload(user),
      ), status: 201
    else
      warden.custom_failure!
      render :json=> user.errors, :status=>422
    end
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
    invitation = Invitation.find_by(invitation_code: code)

    if invitation.nil?
      return render json: { message: "Invitation code is wrong" }, status: 422
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
    invited_user = Invitation.find_by(invitation_code: code)&.user

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
    invitation = Invitation.find_by(invitation_code: code)
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
