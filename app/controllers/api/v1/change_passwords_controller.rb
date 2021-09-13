class Api::V1::ChangePasswordsController < Api::V1::ApiController
  def update
    if current_user.user_groups.each { |ug| p ug.group_label == 'admin' }
      user = User.find_by(id: params[:id])
      if user.update(password: update_params[:password], password_confirmation: update_params[:password_confirmation])
        head :ok
      else
        render json: { error: user.errors }, status: 422
      end
    else
      render json: { error: 'You are not admin' }, status: 422
    end
  end

  private

  def update_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
