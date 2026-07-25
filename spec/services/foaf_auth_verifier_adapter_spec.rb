require 'rails_helper'

RSpec.describe 'shared auth verifier adapter', type: :model, skip_hooks: true do
  around do |example|
    original = ENV['FOAF_SHARED_AUTH_VERIFIER']
    ENV['FOAF_SHARED_AUTH_VERIFIER'] = 'true'
    example.run
  ensure
    ENV['FOAF_SHARED_AUTH_VERIFIER'] = original
  end

  it 'routes RS256 auth tokens through Foaf::Auth::Verifier' do
    token = JWT.encode(
      { sub: 'foaf-id', aud: 'growoperative', exp: 10.minutes.from_now.to_i },
      OpenSSL::PKey::RSA.generate(2048),
      'RS256',
      kid: 'shared-kid'
    )
    claims = { 'sub' => 'foaf-id', 'aud' => 'growoperative' }
    allow(FoafAuthVerifier).to receive(:verify)
      .with(token, request_id: nil)
      .and_return(claims)

    expect(JwtDecodingService.new(token).decrypt!).to eq(claims)
  end

  it 'keeps the HS256 bridge on the application path' do
    user = User.create!(
      user_name: 'shared_auth_bridge',
      password: 'password123',
      foaf_id: SecureRandom.uuid
    )
    legacy = JwtGenerationService.new(user).token

    expect(FoafAuthVerifier).not_to receive(:verify)
    expect(JwtDecodingService.new(legacy).decrypt!['sub']).to eq(user.foaf_id)
  ensure
    User.where(user_name: 'shared_auth_bridge').delete_all
  end
end
