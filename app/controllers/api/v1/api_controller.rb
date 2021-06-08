class Api::V1::ApiController < ApplicationController
  protect_from_forgery prepend: true, with: :exception

  skip_before_action :verify_authenticity_token

  before_action :authenticate!

  def render_resource(resource)
    if resource.errors.empty?
      render json: resource
    else
      validation_error(resource)
    end
  end

  def validation_error(resource)
    render json: {
      errors: [
        {
          status: '400',
          title: 'Bad Request',
          detail: resource.errors,
          code: '100'
        }
      ]
    }, status: :bad_request
  end

  def current_user
    jwt = cookies.signed[:jwt]
    return unless jwt

    decoded = JwtDecodingService.new(jwt).decrypt!
    @current_user ||= User.find_by(id: decoded['sub']['user_id'])
  end

  def assign_jwt_cookies(user)
    return unless user

    token = JwtGenerationService.new(user_id: user.id).token
    time = 1.year.from_now
    cookies.signed[:jwt] = { value: token, expires: time, httponly: true }
  end

  private

  def authenticate!
    unauthorized! unless current_user
  end

  def unauthorized!
    head(:unauthorized)
  end
end
