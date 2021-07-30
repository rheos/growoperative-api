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
    params.permit(:user_name, :password, :password_conformation, :invited_code)
  end

  def invitation_limit
    invited_user = Invitation.find_by(invitation_code: params[:invited_code])
    if invited_user.pending?
      unless invited_user.try(:user).try(:ramaining_invitation_limit) >= 0
        render json: {
          message: "Invitation limit over"
        }, status: 422
      end
    elsif invited_user.accepted?
      render json: {
          message: "Invitation code is already used"
        }, status: 422
    else
      render json: {
        message: "Invitation code is wrong"
      }, status: 422
    end
  end

  def check_chain_limit
    global_setting = GlobalSetting.find_by(setting: "ChainLimit")
    invited_user = Invitation.find_by(invitation_code: params[:invited_code]).try(:user)
    if invited_user
      unless invited_user.depth < global_setting.value
        render json: {
          message: "Chain limit over"
        }, status: 422
      end
    else
      render json: {
        message: "Invitation code is wrong"
      }, status: 422
    end
  end
end
