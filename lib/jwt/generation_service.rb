require 'digest'

class JwtGenerationService
  SIGNING_ALGORITHM = 'HS256'

  def initialize(user_id)
    @user_id = user_id
  end

  def token
    JWT.encode(payload, secret, SIGNING_ALGORITHM)
  end

  private

  def payload
    @payload ||= { iat: Time.now.to_i, sub: @user_id }
  end

  def secret
    ENV['RAILS_SECRET_KEY_BASE']
  end
end
