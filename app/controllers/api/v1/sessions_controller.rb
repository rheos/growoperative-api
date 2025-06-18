class Api::V1::SessionsController < Api::V1::ApiController
  skip_before_action :authenticate!, only: :create

  def show
    render json: UserSerializer.new(current_user), status: 200
  end

  def create
    Rails.logger.debug("Login attempt - Params: #{params.inspect}")
    
    user = User.find_by(user_name: params[:user_name])
    Rails.logger.debug("User found: #{user.present?}")
    
    if user&.valid_password?(params[:password])
      Rails.logger.debug("Password valid for user: #{user.user_name}")
      begin
        token = JwtGenerationService.new(user.id).token
        Rails.logger.debug("JWT token generated successfully")
        render json: { token: token }, status: :ok
      rescue JwtGenerationService::JWTGenerationError => e
        Rails.logger.error("JWT Generation failed: #{e.message}")
        render json: { error: "Authentication failed: #{e.message}" }, status: :internal_server_error
      rescue StandardError => e
        Rails.logger.error("Unexpected error during login: #{e.message}")
        render json: { error: "An unexpected error occurred during login" }, status: :internal_server_error
      end
    else
      Rails.logger.warn("Failed login attempt for user: #{params[:user_name]}")
      render json: { error: "Username or password are invalid" }, status: :unauthorized
    end
  end

  def destroy
    cookies.delete :jwt
    head :ok
  end

  private

  def user
    @user ||= User.find_by(user_name: create_params[:username])
  end

  def create_params
    params.permit(:username, :password)
  end
end
