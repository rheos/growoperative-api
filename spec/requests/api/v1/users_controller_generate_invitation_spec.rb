require 'rails_helper'

# Job 51 — railsbackend dual-write issuance (prompt 07). Exercises
# UsersController#generate_invitation under the FOAF_AUTH_INVITE_BRIDGE_ENABLED
# bridge: bridge-off = pure local; bridge-on = best-effort FOAF mint with the
# single-code mirror for auto-generators, and FOAF-first for custom codes.
#
# THE LOAD-BEARING INVARIANT (single-code mirror): when FOAF mints, the code
# DISPLAYED to the inviter must be the same code redemption resolves. The
# "mirrors the displayed code into the redeemable local row" example is the
# proof — never displaying FOAF's code while storing a different local code.
RSpec.describe 'UsersController#generate_invitation dual-write', type: :request, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) do
    User.create!(user_name: 'gi_inviter', password: password,
                 invite_limit: 50, foaf_id: SecureRandom.uuid)
  end
  let(:auth_headers) { { 'Authorization' => "Bearer #{JwtGenerationService.new(inviter).token}" } }

  def parsed
    JSON.parse(response.body)
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def with_bridge(on)
    prior = ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED']
    ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = on ? 'true' : nil
    yield
  ensure
    ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = prior
  end

  describe 'bridge OFF (default — pure local, no FOAF)' do
    it 'creates a local row and never calls FOAF' do
      with_bridge(false) do
        expect(AuthFoafClient).not_to receive(:create_invitation)

        get '/v1/users/generate_invitation', params: { user_type: 'consumer' }, headers: auth_headers
        expect(response).to have_http_status(200)
      end

      inv = Invitation.order(created_at: :desc).first
      expect(inv).to be_present
      expect(inv.invitation_code).to be_present
      expect(inv.invitation_code.length).to eq(8)
      expect(inv.auth_invitation_id).to be_nil
      expect(inv.foaf_invitation_state).to be_nil
    end

    # Fix A — a custom request when the bridge is OFF must reject loudly, not
    # silently downgrade to a random auto-generated code. Custom issuance
    # reserves a namespace string in FOAF, which is unavailable without the
    # bridge — same 503 as custom + FOAF-down. No local row is created, and
    # FOAF is never called (there's no bridge to call through).
    it 'rejects custom with 503 foaf_unavailable_for_custom and NO local row, never calling FOAF' do
      with_bridge(false) do
        expect(AuthFoafClient).not_to receive(:create_invitation)

        expect {
          get '/v1/users/generate_invitation',
              params: { user_type: 'consumer', generator: 'custom', custom_code: 'friends1', multi_use: 'true' },
              headers: auth_headers
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(503)
        expect(parsed['error']).to eq('foaf_unavailable_for_custom')
      end
    end

    # The custom + !multi_use 422 applies FIRST, regardless of bridge state —
    # a custom single-use request is 422 (not the bridge-off 503) and never
    # touches FOAF or the local table.
    it 'still returns 422 custom_requires_multi_use for custom + single-use (bridge off)' do
      with_bridge(false) do
        expect(AuthFoafClient).not_to receive(:create_invitation)

        expect {
          get '/v1/users/generate_invitation',
              params: { user_type: 'consumer', generator: 'custom', custom_code: 'friends1', multi_use: 'false' },
              headers: auth_headers
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(422)
        expect(parsed['error']).to eq('custom_requires_multi_use')
      end
    end
  end

  describe 'bridge ON — auto-generator success (201)' do
    it 'stores auth_invitation_id, code_strategy and marks synced' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_return(
          [201, {
            'invitation_id' => 'foaf-inv-1',
            'code' => 'abcd1234',
            'display_code' => 'abcd 1234',
            'code_strategy' => 'hexstring'
          }]
        )

        get '/v1/users/generate_invitation', params: { user_type: 'consumer' }, headers: auth_headers
        expect(response).to have_http_status(200)
      end

      inv = Invitation.order(created_at: :desc).first
      expect(inv.auth_invitation_id).to eq('foaf-inv-1')
      expect(inv.code_strategy).to eq('hexstring')
      expect(inv.foaf_invitation_state).to eq(Invitation::FOAF_STATE_SYNCED)
    end

    # THE MIRROR TEST — the displayed code IS the redeemable code.
    it 'mirrors FOAF code into the local row so the displayed code redeems' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_return(
          [201, {
            'invitation_id' => 'foaf-inv-2',
            'code' => 'abcd1234',
            'display_code' => 'abcd 1234',
            'code_strategy' => 'hexstring'
          }]
        )

        get '/v1/users/generate_invitation', params: { user_type: 'consumer' }, headers: auth_headers
        expect(response).to have_http_status(200)
      end

      displayed = parsed['display_code']
      expect(displayed).to eq('abcd 1234')

      inv = Invitation.order(created_at: :desc).first
      # The stored redemption key is the canonical form of FOAF's code.
      expect(inv.invitation_code).to eq('ABCD1234')
      # And redemption resolves the SAME row from the displayed code — the
      # invariant: never display a code that doesn't redeem.
      expect(Invitation.find_by_code(displayed)).to eq(inv)
      expect(Invitation.find_by_code('abcd1234')).to eq(inv)
    end

    it 'forwards generator + multi_use to FOAF' do
      with_bridge(true) do
        expect(AuthFoafClient).to receive(:create_invitation).with(
          hash_including(generator: 'pronounceable', multi_use: true)
        ).and_return([201, { 'invitation_id' => 'foaf-inv-3', 'code' => 'mavo-leni', 'display_code' => 'mavo-leni', 'code_strategy' => 'pronounceable' }])

        get '/v1/users/generate_invitation',
            params: { user_type: 'consumer', generator: 'pronounceable', multi_use: 'true' },
            headers: auth_headers
        expect(response).to have_http_status(200)
      end
    end
  end

  describe 'bridge ON — auto-generator, FOAF down (fire-and-forget fallback)' do
    it 'still creates a local row (unsynced) and returns 200 on a FOAF 500' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_return([500, { 'error' => 'boom' }])

        get '/v1/users/generate_invitation', params: { user_type: 'consumer' }, headers: auth_headers
        expect(response).to have_http_status(200)
      end

      inv = Invitation.order(created_at: :desc).first
      expect(inv).to be_present
      expect(inv.invitation_code).to be_present
      expect(inv.invitation_code.length).to eq(8)
      expect(inv.auth_invitation_id).to be_nil
      expect(inv.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
    end

    it 'still creates a local row (unsynced) when the FOAF call raises' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_raise(StandardError, 'connection refused')

        get '/v1/users/generate_invitation', params: { user_type: 'consumer' }, headers: auth_headers
        expect(response).to have_http_status(200)
      end

      inv = Invitation.order(created_at: :desc).first
      expect(inv.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
      # The displayed code is still the redeemable local fallback code.
      expect(Invitation.find_by_code(parsed['display_code'])).to eq(inv)
    end
  end

  describe 'bridge ON — custom generator' do
    let(:custom_params) { { user_type: 'consumer', generator: 'custom', custom_code: 'friends1', multi_use: 'true' } }

    it 'on 201 creates the local row mirroring FOAF code and marks synced' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_return(
          [201, {
            'invitation_id' => 'foaf-custom-1',
            'code' => 'friends1',
            'display_code' => 'friends1',
            'code_strategy' => 'custom'
          }]
        )

        get '/v1/users/generate_invitation', params: custom_params, headers: auth_headers
        expect(response).to have_http_status(200)
      end

      inv = Invitation.order(created_at: :desc).first
      expect(inv.auth_invitation_id).to eq('foaf-custom-1')
      expect(inv.code_strategy).to eq('custom')
      expect(inv.foaf_invitation_state).to eq(Invitation::FOAF_STATE_SYNCED)
      expect(Invitation.find_by_code(parsed['display_code'])).to eq(inv)
    end

    it 'forwards 409 code_taken and creates NO local row' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_return([409, { 'error' => 'code_taken' }])

        expect {
          get '/v1/users/generate_invitation', params: custom_params, headers: auth_headers
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(409)
        expect(parsed['error']).to eq('code_taken')
      end
    end

    it 'returns 503 foaf_unavailable_for_custom and NO local row when FOAF is down' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_raise(StandardError, 'connection refused')

        expect {
          get '/v1/users/generate_invitation', params: custom_params, headers: auth_headers
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(503)
        expect(parsed['error']).to eq('foaf_unavailable_for_custom')
      end
    end

    it 'returns 503 and NO local row on a non-201/409 FOAF status' do
      with_bridge(true) do
        allow(AuthFoafClient).to receive(:create_invitation).and_return([500, { 'error' => 'boom' }])

        expect {
          get '/v1/users/generate_invitation', params: custom_params, headers: auth_headers
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(503)
        expect(parsed['error']).to eq('foaf_unavailable_for_custom')
      end
    end

    it 'rejects custom + multi_use:false with 422 custom_requires_multi_use (before any FOAF call)' do
      with_bridge(true) do
        expect(AuthFoafClient).not_to receive(:create_invitation)

        expect {
          get '/v1/users/generate_invitation',
              params: { user_type: 'consumer', generator: 'custom', custom_code: 'friends1', multi_use: 'false' },
              headers: auth_headers
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(422)
        expect(parsed['error']).to eq('custom_requires_multi_use')
      end
    end

    # Fix C — a custom code can't be minted without a FOAF identity to mint
    # against. Guard before the FOAF call so a missing foaf_id returns 503
    # foaf_unavailable_for_custom (not a mislabeled FOAF 404), and creates NO
    # local row. FOAF is never called.
    context 'when the inviter has no foaf_id' do
      it 'returns 503 foaf_unavailable_for_custom and NO local row, never calling FOAF' do
        # The inviter has a real foaf_id so the JWT mints (JwtGenerationService
        # requires one) — build the auth header FIRST, then blank
        # current_user.foaf_id at request time to exercise the guard. The guard
        # keys off foaf_id.blank?.
        headers = auth_headers
        allow_any_instance_of(User).to receive(:foaf_id).and_return('')

        with_bridge(true) do
          expect(AuthFoafClient).not_to receive(:create_invitation)

          expect {
            get '/v1/users/generate_invitation', params: custom_params, headers: headers
          }.not_to change(Invitation, :count)
          expect(response).to have_http_status(503)
          expect(parsed['error']).to eq('foaf_unavailable_for_custom')
        end
      end
    end
  end

  describe 'invitation limit' do
    it 'returns 422 when the inviter is out of invites' do
      inviter.update!(invite_limit: 0)
      get '/v1/users/generate_invitation', params: { user_type: 'consumer' }, headers: auth_headers
      expect(response).to have_http_status(422)
      expect(parsed['message']).to eq('Invitation limit over')
    end
  end
end
