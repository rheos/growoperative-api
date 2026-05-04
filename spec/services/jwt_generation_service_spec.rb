require 'rails_helper'

# Unit coverage for the v1 token claim shape (master plan §JWT Contract).
# These claims are load-bearing for the auth.foaf.io migration: app
# verifiers (job 13+ saga + job 36 Rails verifier) key off `sub = foaf_id`,
# `aud`, and the bridge-only `legacy_uid`.
RSpec.describe JwtGenerationService do
  let(:user) do
    User.create!(
      user_name: 'jwt_user',
      email: 'jwt_user@example.com',
      password: 'bobsentme!',
      password_confirmation: 'bobsentme!',
    )
  end

  def decoded(token)
    JWT.decode(token, ENV['SECRET_KEY_BASE'], true, { algorithm: 'HS256' }).first
  end

  describe '#token' do
    it 'emits sub = foaf_id (string), not nested user_id' do
      token = described_class.new(user).token
      claims = decoded(token)
      expect(claims['sub']).to eq(user.foaf_id)
      expect(claims['sub']).to be_a(String)
    end

    it 'includes aud, defaulting to "growoperative"' do
      token = described_class.new(user).token
      claims = decoded(token)
      expect(claims['aud']).to eq('growoperative')
    end

    it 'allows aud override (FOAF_AUD env or kwarg) for orchardly et al.' do
      token = described_class.new(user, aud: 'orchardly').token
      claims = decoded(token)
      expect(claims['aud']).to eq('orchardly')
    end

    it 'includes legacy_uid (numeric users.id) as bridge-only fallback metadata' do
      token = described_class.new(user).token
      claims = decoded(token)
      expect(claims['legacy_uid']).to eq(user.id)
    end

    it 'includes a fresh jti (UUID) per token' do
      a = described_class.new(user).token
      b = described_class.new(user).token
      expect(decoded(a)['jti']).not_to eq(decoded(b)['jti'])
      expect(decoded(a)['jti']).to match(/\A[0-9a-f-]{36}\z/i)
    end

    it 'includes user_name and email when present' do
      token = described_class.new(user).token
      claims = decoded(token)
      expect(claims['user_name']).to eq(user.user_name)
      expect(claims['email']).to eq(user.email)
    end

    it 'omits email when the user has none' do
      no_email = User.create!(
        user_name: 'no_email_user',
        password: 'bobsentme!',
        password_confirmation: 'bobsentme!',
      )
      token = described_class.new(no_email).token
      expect(decoded(token)).not_to have_key('email')
    end

    it 'does not emit iss until Phase-3 cutover (RS256 + JWKS)' do
      token = described_class.new(user).token
      expect(decoded(token)).not_to have_key('iss')
    end

    it 'raises when the user is nil' do
      expect { described_class.new(nil).token }
        .to raise_error(JwtGenerationService::JWTGenerationError)
    end
  end
end
