class Api::V1::SessionsController < Api::V1::ApiController
  skip_before_action :authenticate!, only: :create

  def show
    render json: UserSerializer.new(current_user), status: 200
  end

  def create
    if user&.valid_password?(create_params[:password])
      assign_jwt_cookies(user)
      render json: UserSerializer.new(user), status: 200
    else
      render json: { error: 'Username or password are invalid' }, status: 401
    end
  end

  def destroy
    cookies.delete :jwt
    head :ok
  end

  private

  def user
    @user ||= User.find_by(user_name: create_params[:user_name])
  end

  def create_params
    params.permit(:user_name, :password)
  end
end
