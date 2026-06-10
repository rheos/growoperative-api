require 'rails_helper'

# Job 51 — the AuthFoafClient issuance methods added in prompt 07. These
# stub the HTTP transport (get_service_json / post_json) at the instance
# level and assert the wrapper logic: availability boolean coercion, the
# non-200 -> Error raise, and the disable/enable request shapes.
RSpec.describe AuthFoafClient, '.invitation issuance methods' do
  before do
    # Availability + disable/enable hit the service-token channel; provide a
    # base_url and service_token so the methods don't blow up on ENV fetch.
    allow(AuthFoafClient).to receive(:base_url).and_return('https://dauth.foaf.io')
    allow(AuthFoafClient).to receive(:service_token).and_return('test-service-token')
    allow(AuthFoafClient).to receive(:audience).and_return('growoperative')
  end

  describe '.invitation_code_available?' do
    it 'returns true when FOAF reports available: true' do
      allow_any_instance_of(AuthFoafClient)
        .to receive(:get_service_json)
        .and_return([200, { 'available' => true }])

      expect(AuthFoafClient.invitation_code_available?(code: 'friends1', target_app: 'growoperative')).to eq(true)
    end

    it 'returns false when FOAF reports available: false' do
      allow_any_instance_of(AuthFoafClient)
        .to receive(:get_service_json)
        .and_return([200, { 'available' => false }])

      expect(AuthFoafClient.invitation_code_available?(code: 'taken1', target_app: 'growoperative')).to eq(false)
    end

    it 'raises AuthFoafClient::Error on a non-200 response' do
      allow_any_instance_of(AuthFoafClient)
        .to receive(:get_service_json)
        .and_return([500, { 'error' => 'boom' }])

      expect {
        AuthFoafClient.invitation_code_available?(code: 'whatever', target_app: 'growoperative')
      }.to raise_error(AuthFoafClient::Error)
    end

    it 'requests the availability endpoint with the code and target_app' do
      expect_any_instance_of(AuthFoafClient)
        .to receive(:get_service_json)
        .with(a_string_matching(%r{/v1/internal/invitations/availability\?}))
        .and_return([200, { 'available' => true }])

      AuthFoafClient.invitation_code_available?(code: 'friends1', target_app: 'growoperative')
    end
  end

  describe '.disable_invitation' do
    it 'posts to the disable endpoint with the service token and returns the body' do
      expect_any_instance_of(AuthFoafClient)
        .to receive(:post_json)
        .with('/v1/internal/invitations/foaf-inv-1/disable', {}, service_token: true)
        .and_return([200, { 'status' => 'disabled' }])

      expect(AuthFoafClient.disable_invitation(invitation_id: 'foaf-inv-1')).to eq({ 'status' => 'disabled' })
    end

    it 'raises AuthFoafClient::Error on failure' do
      allow_any_instance_of(AuthFoafClient)
        .to receive(:post_json)
        .and_return([404, { 'error' => 'not_found' }])

      expect {
        AuthFoafClient.disable_invitation(invitation_id: 'missing')
      }.to raise_error(AuthFoafClient::Error)
    end
  end

  describe '.enable_invitation' do
    # Expiry is enforced FOAF-side (enable! preserves the row's own expiry, W7);
    # railsbackend sends an empty body and the enable endpoint ignores any
    # expires_at, so the wrapper takes no expires_at arg.
    it 'posts an empty body on re-enable (no expires_at plumbing)' do
      expect_any_instance_of(AuthFoafClient)
        .to receive(:post_json)
        .with('/v1/internal/invitations/foaf-inv-1/enable', {}, service_token: true)
        .and_return([200, { 'status' => 'active' }])

      expect(AuthFoafClient.enable_invitation(invitation_id: 'foaf-inv-1')).to eq({ 'status' => 'active' })
    end

    it 'raises AuthFoafClient::Error on failure' do
      allow_any_instance_of(AuthFoafClient)
        .to receive(:post_json)
        .and_return([409, { 'error' => 'reclaimed' }])

      expect {
        AuthFoafClient.enable_invitation(invitation_id: 'foaf-inv-1')
      }.to raise_error(AuthFoafClient::Error)
    end
  end
end
