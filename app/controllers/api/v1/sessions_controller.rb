class Api::V1::SessionsController < Api::V1::ApiController
  skip_before_action :authenticate!, only: :create

  def show
    token = JwtGenerationService.new(current_user).token
    render json: UserSerializer.new(current_user).serializable_hash.merge(
      token: token,
      identity: identity_payload(current_user),
    ), status: 200
  end

  def create
    user = User.find_by(user_name: params[:username])

    if user&.valid_password?(params[:password])
      assign_jwt_cookies(user)
      token = JwtGenerationService.new(user).token
      render json: UserSerializer.new(user).serializable_hash.merge(
        token: token,
        identity: identity_payload(user),
      ), status: 200
    else
      # Master plan §Logging and Audit / Job 12: log the *outcome*, not
      # the submitted handle. Per-IP / handle bucketing for the failed-
      # login lockout (master plan §Account Lockout, Job 18) lives in
      # auth.foaf.io; logging the raw handle here would defeat that.
      Rails.logger.warn("Failed login attempt")
      render json: { error: "Username or password are invalid" }, status: :unauthorized
    end
  end

  def destroy
    # Get the current JWT token before deleting the cookie
    jwt = cookies.signed[:jwt]
    
    # Add the token to the blacklist if it exists
    if jwt.present?
      begin
        decoded = JwtDecodingService.new(jwt).decrypt!
        # Add to blacklist using datetime instead of Unix timestamp
        JWTBlacklist.create!(
          jti: decoded['jti'] || SecureRandom.uuid,
          exp: Time.at(decoded['exp'] || 1.year.from_now.to_i)  # Convert to datetime
        )
      rescue JwtDecodingService::JWTDecodingError => e
        Rails.logger.warn("Failed to blacklist JWT on logout due to decoding error: #{e.message}")
      end
    end
    
    # Delete the cookie
    if Rails.env.development?
      cookies.delete :jwt  # No domain needed for development
    else
      cookies.delete :jwt, domain: ENV.fetch('COOKIE_DOMAIN', '.growoperative.app')
    end
    
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
