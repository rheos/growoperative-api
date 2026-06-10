require 'rails_helper'

# Job 51 Phase 1 — InvitationIssuanceReconciler forward-reconciles `unsynced`
# issuance rows into FOAF. These pin the per-row outcome contract (201 ->
# reconciled, 409 -> failed, error/non-201 -> left unsynced), the bridge gate,
# and idempotency.
RSpec.describe InvitationIssuanceReconciler, type: :service, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) { User.create!(user_name: 'recon_inviter', password: password, foaf_id: SecureRandom.uuid) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def with_bridge(on)
    prior = ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED']
    ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = on ? 'true' : nil
    yield
  ensure
    ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = prior
  end

  def unsynced_row(code: 'UNSYNC01')
    inviter.invitations.create!(
      user_type: 'consumer', status: 0, invitation_code: code,
      foaf_invitation_state: Invitation::FOAF_STATE_UNSYNCED
    )
  end

  describe 'bridge gate' do
    it 'is a no-op and makes no FOAF calls when the bridge is off' do
      row = unsynced_row
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(false) do
        summary = described_class.run
        expect(summary[:processed]).to eq(0)
        expect(summary[:skipped_reason]).to eq('bridge_off')
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
    end
  end

  describe 'bridge on' do
    it 'stores auth_invitation_id and marks reconciled on a 201' do
      row = unsynced_row
      allow(AuthFoafClient).to receive(:create_invitation).and_return(
        [201, { 'invitation_id' => 'foaf-abc', 'code' => 'mavoleni', 'code_strategy' => 'pronounceable' }]
      )

      with_bridge(true) do
        summary = described_class.run
        expect(summary[:reconciled]).to eq(1)
      end

      row.reload
      expect(row.auth_invitation_id).to eq('foaf-abc')
      expect(row.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
      # Redemption stays local: the redeemable code is NOT overwritten.
      expect(row.invitation_code).to eq('UNSYNC01')
    end

    it 'marks the row failed on a 409 code_taken' do
      row = unsynced_row
      allow(AuthFoafClient).to receive(:create_invitation).and_return([409, { 'error' => 'code_taken' }])

      with_bridge(true) do
        summary = described_class.run
        expect(summary[:failed]).to eq(1)
      end

      row.reload
      expect(row.foaf_invitation_state).to eq(Invitation::FOAF_STATE_FAILED)
      expect(row.auth_invitation_id).to be_nil
    end

    it 'leaves the row unsynced on a non-201/non-409 FOAF response' do
      row = unsynced_row
      allow(AuthFoafClient).to receive(:create_invitation).and_return([500, { 'error' => 'boom' }])

      with_bridge(true) do
        summary = described_class.run
        expect(summary[:errored]).to eq(1)
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
    end

    it 'leaves the row unsynced when the FOAF call raises' do
      row = unsynced_row
      allow(AuthFoafClient).to receive(:create_invitation).and_raise(StandardError, 'connection refused')

      with_bridge(true) do
        summary = described_class.run
        expect(summary[:errored]).to eq(1)
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
    end

    it 'skips a row whose inviter has no foaf_id and leaves it unsynced' do
      # users.foaf_id is NOT NULL at the DB level, so the only way a row's
      # inviter presents a blank foaf_id is a transient association state.
      # Stub the loaded user to exercise the reconciler's blank-foaf guard.
      row = unsynced_row(code: 'NOFOAF01')
      blank_foaf_user = inviter.tap { |u| allow(u).to receive(:foaf_id).and_return(nil) }
      allow_any_instance_of(Invitation).to receive(:user).and_return(blank_foaf_user)
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(true) do
        summary = described_class.run
        expect(summary[:skipped]).to eq(1)
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
    end

    it 'is idempotent: synced/reconciled/failed rows are not candidates' do
      synced = inviter.invitations.create!(
        user_type: 'consumer', status: 0, invitation_code: 'SYNCED01',
        foaf_invitation_state: Invitation::FOAF_STATE_SYNCED, auth_invitation_id: 'foaf-synced'
      )
      reconciled = inviter.invitations.create!(
        user_type: 'consumer', status: 0, invitation_code: 'RECON01',
        foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED, auth_invitation_id: 'foaf-recon'
      )
      failed = inviter.invitations.create!(
        user_type: 'consumer', status: 0, invitation_code: 'FAILED01',
        foaf_invitation_state: Invitation::FOAF_STATE_FAILED
      )
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(true) do
        summary = described_class.run
        expect(summary[:processed]).to eq(0)
      end

      expect(synced.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_SYNCED)
      expect(reconciled.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
      expect(failed.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_FAILED)
    end

    it 'passes the row strategy and multi_use flag through to FOAF' do
      row = inviter.invitations.create!(
        user_type: 'consumer', status: 0, invitation_code: 'MULTI01', multi_use: true,
        foaf_invitation_state: Invitation::FOAF_STATE_UNSYNCED
      )
      expect(AuthFoafClient).to receive(:create_invitation).with(
        inviter_foaf_id: inviter.foaf_id,
        target_app: 'growoperative',
        generator: 'pronounceable',
        multi_use: true,
        expires_in_seconds: kind_of(Integer)
      ).and_return([201, { 'invitation_id' => 'foaf-multi', 'code_strategy' => 'pronounceable' }])

      with_bridge(true) { described_class.run }
      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
    end
  end
end
