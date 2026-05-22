# Job 43: railsbackend's auth controllers proxy to auth.foaf.io. Specs
# don't have a real auth service to talk to, so we stub AuthFoafClient
# at the class level. The stub returns [status, body] tuples shaped
# like the real responses, with HS256 tokens minted by the existing
# JwtGenerationService — that token verifies via JwtDecodingService's
# HS256 bridge path (FOAF_AUTH_HS256_BRIDGE_ENABLED defaults true in
# test). Production runs RS256 issued by auth.foaf.io.
#
# Specs that exercise the proxy itself (e.g. asserting AuthFoafClient
# is called with specific args, or testing 4xx/5xx error paths) can
# override these stubs with `allow(AuthFoafClient).to receive(...)`.

RSpec.configure do |config|
  config.before(:each) do
    allow(AuthFoafClient).to receive(:login) do |user_name:, password:|
      user = User.find_by(user_name: user_name.to_s.downcase)
      if user&.valid_password?(password)
        token = JwtGenerationService.new(user).token
        [200, {
          'token' => token,
          'identity' => {
            'foaf_id' => user.foaf_id,
            'user_name' => user.user_name,
            'display_name' => user.display_name,
            'first_name' => user.first_name,
            'last_name' => user.last_name,
            'email' => user.email,
            'avatar_url' => nil,
            'created_at' => user.created_at&.iso8601,
            'updated_at' => user.updated_at&.iso8601,
          }
        }]
      else
        [401, { 'error' => 'Invalid credentials' }]
      end
    end

    allow(AuthFoafClient).to receive(:signup) do |user_name:, password:, email: nil, first_name: nil, last_name: nil, display_name: nil, recovery_phrase_acknowledged: false|
      foaf_id = SecureRandom.uuid
      [201, {
        'token' => 'test-rs256-token',
        'identity' => {
          'foaf_id' => foaf_id,
          'user_name' => user_name,
          'display_name' => display_name,
          'first_name' => first_name,
          'last_name' => last_name,
          'email' => email,
        }
      }]
    end

    allow(AuthFoafClient).to receive(:demo_token) do |foaf_id:, lifetime_seconds: nil|
      user = User.find_by(foaf_id: foaf_id)
      token = user ? JwtGenerationService.new(user).token : 'test-demo-token'
      [200, {
        'token' => token,
        'kid' => 'test-demo',
        'foaf_id' => foaf_id,
        'audience' => 'growoperative',
        'expires_at' => (Time.current + 1.hour).iso8601
      }]
    end

    allow(AuthFoafClient).to receive(:change_password) do |current_password:, new_password:, bearer:|
      [200, { 'token' => 'test-rs256-refresh' }]
    end

    allow(AuthFoafClient).to receive(:refresh_session) do |bearer:|
      decoded = JwtDecodingService.new(bearer).decrypt! rescue nil
      foaf_id = decoded && decoded['sub']
      user = foaf_id && User.find_by(foaf_id: foaf_id)
      if user
        token = JwtGenerationService.new(user).token
        [200, {
          'token' => token,
          'identity' => {
            'foaf_id' => user.foaf_id,
            'user_name' => user.user_name,
            'display_name' => user.display_name,
            'first_name' => user.first_name,
            'last_name' => user.last_name,
            'email' => user.email,
            'avatar_url' => nil,
            'created_at' => user.created_at&.iso8601,
            'updated_at' => user.updated_at&.iso8601,
          }
        }]
      else
        [401, { 'error' => 'invalid bearer' }]
      end
    end

    allow(AuthFoafClient).to receive(:identity_by_handle) do |handle:|
      user = User.find_by(user_name: handle.to_s.downcase)
      if user
        [200, {
          'foaf_id' => user.foaf_id,
          'user_name' => user.user_name,
          'display_name' => user.display_name,
          'avatar_url' => nil,
        }]
      else
        [404, { 'error' => 'not_found' }]
      end
    end
  end
end
