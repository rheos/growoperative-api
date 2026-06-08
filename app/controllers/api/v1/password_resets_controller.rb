# Thin proxy to auth.foaf.io's password-reset-by-email surface. The app talks
# only to railsbackend, so these mirror foaf-auth's /v1/password_reset/* and
# forward the (enumeration-safe) response through unchanged. Unauthenticated —
# `request` mints + emails a token, `confirm` consumes it and sets the password.
class Api::V1::PasswordResetsController < Api::V1::ApiController
  skip_before_action :authenticate!

  def create
    status, body = AuthFoafClient.password_reset_request(
      email: params[:email].presence || params[:username].presence || params[:user_name],
      origin: params[:origin]
    )
    render json: body, status: status
  end

  def confirm
    new_password = params[:password].to_s
    confirmation = params[:password_confirmation].to_s
    if new_password.blank? || new_password != confirmation
      return render json: { message: 'Invalid password params' }, status: 422
    end

    status, body = AuthFoafClient.password_reset_confirm(token: params[:token], password: new_password)
    render json: body, status: status
  end
end
