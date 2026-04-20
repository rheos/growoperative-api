class Api::V1::RegistrationsController < Api::V1::ApiController
  skip_before_action :authenticate!

  before_action :invitation_limit, :check_chain_limit, only: [:create]

  respond_to :json

  def create
    user = User.new(sign_up_params)
    if user.save
      assign_jwt_cookies(user)
      render json: UserSerializer.new(user), status: 201
    else
      warden.custom_failure!
      render :json=> user.errors, :status=>422
    end
  end

  private

  def sign_up_params
    # Accept both the legacy flat-param shape (old platform/) and the new
    # nested-under-:user shape (growoperative-app). Tolerate both invite_code
    # spellings since the legacy contract had `invited_code`.
    source = params[:user].present? ? params[:user] : params
    permitted = source.permit(
      :user_name, :password, :password_confirmation, :password_conformation,
      :first_name, :last_name, :email, :invite_code, :invited_code,
    ).to_h
    # Normalize the misspelled :password_conformation key the User model expects.
    if permitted[:password_confirmation].present? && permitted[:password_conformation].blank?
      permitted[:password_conformation] = permitted[:password_confirmation]
    end
    permitted.delete(:password_confirmation)
    # Same for invite_code → invited_code (the column the User model uses).
    if permitted[:invite_code].present? && permitted[:invited_code].blank?
      permitted[:invited_code] = permitted[:invite_code]
    end
    permitted.delete(:invite_code)
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
end
