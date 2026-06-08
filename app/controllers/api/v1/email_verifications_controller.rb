# Thin proxy to auth.foaf.io's email-verification surface. The app talks only
# to railsbackend, so these mirror foaf-auth's /v1/email_verification/* and
# forward the response through unchanged. `create` is authenticated (it targets
# the calling identity's pending/unverified email via the Bearer token);
# `confirm` is token-only and skips authenticate! so it works from the email
# link with no session.
class Api::V1::EmailVerificationsController < Api::V1::ApiController
  skip_before_action :authenticate!, only: :confirm

  def create
    match = request.headers['Authorization'].to_s.match(/\ABearer\s+(.+)\z/i)
    bearer = match && match[1]

    status, body = AuthFoafClient.email_verification_request(
      bearer: bearer,
      origin: params[:origin]
    )
    render json: body, status: status
  end

  def confirm
    if params[:token].blank?
      return render json: { error: 'Missing token' }, status: 422
    end

    status, body = AuthFoafClient.email_verification_confirm(token: params[:token])
    render json: body, status: status
  end
end
