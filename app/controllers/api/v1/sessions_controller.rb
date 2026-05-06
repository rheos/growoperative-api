class Api::V1::SessionsController < Api::V1::ApiController
  skip_before_action :authenticate!, only: :create

  def show
    # Job 43: proxy to auth.foaf.io's GET /v1/sessions to refresh the
    # bearer. Client passes its current token; auth.foaf.io returns a
    # fresh one alongside the canonical identity.
    bearer = bearer_token
    status, body = AuthFoafClient.refresh_session(bearer: bearer)
    payload = UserSerializer.new(current_user).serializable_hash.merge(
      identity: (body && body['identity']) || identity_payload(current_user)
    )
    payload[:token] = body['token'] if status == 200 && body && body['token']
    render json: payload, status: 200
  end

  def create
    # Job 42: proxy login to auth.foaf.io. railsbackend no longer mints
    # tokens; auth.foaf.io issues an RS256 token signed with this env's
    # active signing key. We stitch it together with the legacy v1
    # envelope so the app's saga doesn't notice the change.
    status, body = AuthFoafClient.login(
      user_name: params[:username],
      password: params[:password]
    )

    if status == 200 && body['token']
      foaf_id = body.dig('identity', 'foaf_id')
      user = User.find_by(foaf_id: foaf_id)
      unless user
        Rails.logger.error("Auth.foaf.io login resolved foaf_id=#{foaf_id.inspect} but no local users row exists")
        return render json: { error: 'Username or password are invalid' }, status: :unauthorized
      end

      clear_legacy_jwt_cookie!
      render json: UserSerializer.new(user).serializable_hash.merge(
        token: body['token'],
        identity: body['identity']
      ), status: 200
    else
      Rails.logger.warn("Failed login attempt (auth.foaf.io status=#{status})")
      render json: { error: 'Username or password are invalid' }, status: :unauthorized
    end
  end

  def destroy
    jwt = bearer_token

    if jwt.present?
      begin
        decoded = JwtDecodingService.new(jwt).decrypt!
        JWTBlacklist.create!(
          jti: decoded['jti'] || SecureRandom.uuid,
          exp: Time.at(decoded['exp'] || 1.year.from_now.to_i)
        )
      rescue JwtDecodingService::JWTDecodingError => e
        Rails.logger.warn("Failed to blacklist JWT on logout due to decoding error: #{e.message}")
      end
    end

    clear_legacy_jwt_cookie!
    head :ok
  end

  private

  def bearer_token
    match = request.headers['Authorization'].to_s.match(/\ABearer\s+(.+)\z/i)
    match && match[1]
  end
end
