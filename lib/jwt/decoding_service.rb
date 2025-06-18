class JwtDecodingService
  SIGNING_ALGORITHM = 'HS256'

  def initialize(token)
    @token = token
  end

  def decrypt!
    JWT.decode(@token, secret).first
  end

  private

  def secret
    ENV['SECRET_KEY_BASE']
  end
end
