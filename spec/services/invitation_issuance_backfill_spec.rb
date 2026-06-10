require 'rails_helper'

# Job 51 Phase 2 — InvitationIssuanceBackfill brings existing local invitation
# issuance rows into FOAF (auth.foaf.io). These pin: dry-run writes nothing;
# live pending rows are seeded with the EXISTING local string (custom_code ==
# invitation_code.downcase, multi_use: true) and the local code is never
# rewritten; already-present codes reconcile without a mint; 409 fails; terminal
# rows are marked reconciled with no mint; and the whole thing is idempotent.
#
# AuthFoafClient is fully stubbed — no real FOAF is ever contacted.
RSpec.describe InvitationIssuanceBackfill, type: :service, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:inviter) { User.create!(user_name: 'backfill_inviter', password: password, foaf_id: SecureRandom.uuid) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def with_bridge(on)
    prior = ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED']
    ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = on ? 'true' : nil
    yield
  ensure
    ENV['FOAF_AUTH_INVITE_BRIDGE_ENABLED'] = prior
  end

  # A LIVE PENDING row: status pending, not disabled, never reached FOAF.
  def pending_row(code: 'MAVOLENI', multi_use: false)
    inviter.invitations.create!(
      user_type: 'consumer', status: :pending, invitation_code: code, multi_use: multi_use,
      foaf_invitation_state: Invitation::FOAF_STATE_UNSYNCED
    )
  end

  describe 'bridge gate' do
    it 'is a no-op and makes no FOAF calls when the bridge is off' do
      row = pending_row
      expect(AuthFoafClient).not_to receive(:invitation_code_available?)
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(false) do
        summary = described_class.run
        expect(summary[:candidates]).to eq(0)
        expect(summary[:skipped_reason]).to eq('bridge_off')
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
    end
  end

  describe 'dry-run (default)' do
    it 'writes nothing and makes no mutating FOAF calls' do
      row = pending_row
      # Availability is read-only and may be consulted to make the preview
      # accurate, but it MUST NOT mint and MUST NOT mutate any row.
      allow(AuthFoafClient).to receive(:invitation_code_available?).and_return(true)
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(true) do
        summary = described_class.run(dry_run: true)
        expect(summary[:candidates]).to eq(1)
        expect(summary[:reconciled_pending]).to eq(1)
      end

      row.reload
      expect(row.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
      expect(row.auth_invitation_id).to be_nil
      expect(row.invitation_code).to eq('MAVOLENI')
    end
  end

  describe 'live run — pending rows' do
    it 'mints a same-code custom seed (custom_code == invitation_code.downcase, multi_use: true) and reconciles' do
      row = pending_row(code: 'MAVOLENI')
      allow(AuthFoafClient).to receive(:invitation_code_available?).with(
        code: 'mavoleni', target_app: 'growoperative'
      ).and_return(true)
      expect(AuthFoafClient).to receive(:create_invitation).with(
        inviter_foaf_id: inviter.foaf_id,
        target_app: 'growoperative',
        generator: 'custom',
        custom_code: 'mavoleni',
        multi_use: true,
        expires_in_seconds: kind_of(Integer)
      ).and_return([201, { 'invitation_id' => 'foaf-mavo', 'code_strategy' => 'custom' }])

      with_bridge(true) do
        summary = described_class.run(dry_run: false)
        expect(summary[:reconciled_pending]).to eq(1)
      end

      row.reload
      expect(row.auth_invitation_id).to eq('foaf-mavo')
      expect(row.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
      # The redemption key is NEVER rewritten.
      expect(row.invitation_code).to eq('MAVOLENI')
    end

    it 'seeds with multi_use: true even for a single-use local row (and never flips the local flag)' do
      row = pending_row(code: 'SINGLE99', multi_use: false)
      allow(AuthFoafClient).to receive(:invitation_code_available?).and_return(true)
      expect(AuthFoafClient).to receive(:create_invitation).with(
        hash_including(generator: 'custom', custom_code: 'single99', multi_use: true)
      ).and_return([201, { 'invitation_id' => 'foaf-single' }])

      with_bridge(true) { described_class.run(dry_run: false) }

      row.reload
      expect(row.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
      expect(row.multi_use).to eq(false)
    end

    it 'reconciles WITHOUT a mint when the code is already present in FOAF (availability false)' do
      row = pending_row(code: 'TAKEN01')
      expect(AuthFoafClient).to receive(:invitation_code_available?).with(
        code: 'taken01', target_app: 'growoperative'
      ).and_return(false)
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(true) do
        summary = described_class.run(dry_run: false)
        expect(summary[:reconciled_already_present]).to eq(1)
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
    end

    it 'proceeds to mint when the availability lookup raises' do
      row = pending_row(code: 'RAISE01')
      allow(AuthFoafClient).to receive(:invitation_code_available?)
        .and_raise(AuthFoafClient::Error.new(status: 503, body: { 'error' => 'down' }))
      expect(AuthFoafClient).to receive(:create_invitation).with(
        hash_including(generator: 'custom', custom_code: 'raise01', multi_use: true)
      ).and_return([201, { 'invitation_id' => 'foaf-raise' }])

      with_bridge(true) do
        summary = described_class.run(dry_run: false)
        expect(summary[:reconciled_pending]).to eq(1)
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
    end

    it 'marks the row failed on a 409 code_taken' do
      row = pending_row(code: 'CONFLICT1')
      allow(AuthFoafClient).to receive(:invitation_code_available?).and_return(true)
      allow(AuthFoafClient).to receive(:create_invitation).and_return([409, { 'error' => 'code_taken' }])

      with_bridge(true) do
        summary = described_class.run(dry_run: false)
        expect(summary[:failed]).to eq(1)
      end

      row.reload
      expect(row.foaf_invitation_state).to eq(Invitation::FOAF_STATE_FAILED)
      expect(row.auth_invitation_id).to be_nil
    end

    it 'tags code_strategy hexstring for a digit-bearing code and pronounceable for alpha-only' do
      hex_row = pending_row(code: 'AB12CD34')   # has digits -> hexstring
      alpha_row = pending_row(code: 'MAVOLENI')  # alpha-only -> pronounceable
      allow(AuthFoafClient).to receive(:invitation_code_available?).and_return(true)
      expect(AuthFoafClient).to receive(:create_invitation)
        .with(hash_including(custom_code: 'ab12cd34'))
        .and_return([201, { 'invitation_id' => 'foaf-hex' }])
      expect(AuthFoafClient).to receive(:create_invitation)
        .with(hash_including(custom_code: 'mavoleni'))
        .and_return([201, { 'invitation_id' => 'foaf-alpha' }])

      with_bridge(true) { described_class.run(dry_run: false) }

      expect(hex_row.reload.code_strategy).to eq('hexstring')
      expect(alpha_row.reload.code_strategy).to eq('pronounceable')
    end
  end

  describe 'terminal rows' do
    it 'marks an accepted (single-use redeemed) row reconciled with NO mint' do
      row = inviter.invitations.create!(
        user_type: 'consumer', status: :accepted, invitation_code: 'USEDONE1',
        foaf_invitation_state: Invitation::FOAF_STATE_UNSYNCED
      )
      expect(AuthFoafClient).not_to receive(:invitation_code_available?)
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(true) do
        summary = described_class.run(dry_run: false)
        expect(summary[:reconciled_terminal]).to eq(1)
      end

      row.reload
      expect(row.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
      expect(row.auth_invitation_id).to be_nil
    end

    it 'marks a disabled (revoked) row reconciled with NO mint' do
      row = inviter.invitations.create!(
        user_type: 'consumer', status: :pending, invitation_code: 'REVOKED1', multi_use: true,
        disabled_at: Time.current, foaf_invitation_state: Invitation::FOAF_STATE_UNSYNCED
      )
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(true) do
        summary = described_class.run(dry_run: false)
        expect(summary[:reconciled_terminal]).to eq(1)
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_RECONCILED)
    end
  end

  describe 'idempotency' do
    it 'excludes reconciled and already-foaf rows; a clean re-run finds 0 candidates' do
      pending_row(code: 'PENDING01')
      inviter.invitations.create!(
        user_type: 'consumer', status: :pending, invitation_code: 'DONE01',
        foaf_invitation_state: Invitation::FOAF_STATE_RECONCILED, auth_invitation_id: 'foaf-done'
      )
      inviter.invitations.create!(
        user_type: 'consumer', status: :pending, invitation_code: 'SYNCED01',
        foaf_invitation_state: Invitation::FOAF_STATE_SYNCED, auth_invitation_id: 'foaf-synced'
      )
      allow(AuthFoafClient).to receive(:invitation_code_available?).and_return(true)
      allow(AuthFoafClient).to receive(:create_invitation)
        .and_return([201, { 'invitation_id' => 'foaf-pending' }])

      with_bridge(true) do
        first = described_class.run(dry_run: false)
        # Only the unsynced pending row is a candidate; the reconciled + the
        # already-foaf (auth_invitation_id present) rows are excluded.
        expect(first[:candidates]).to eq(1)
        expect(first[:reconciled_pending]).to eq(1)

        second = described_class.run(dry_run: false)
        expect(second[:candidates]).to eq(0)
      end
    end

    it 'skips a row whose inviter has no foaf_id and leaves it untouched' do
      row = pending_row(code: 'NOFOAF01')
      blank_foaf_user = inviter.tap { |u| allow(u).to receive(:foaf_id).and_return(nil) }
      allow_any_instance_of(Invitation).to receive(:user).and_return(blank_foaf_user)
      expect(AuthFoafClient).not_to receive(:create_invitation)

      with_bridge(true) do
        summary = described_class.run(dry_run: false)
        expect(summary[:skipped_no_foaf]).to eq(1)
      end

      expect(row.reload.foaf_invitation_state).to eq(Invitation::FOAF_STATE_UNSYNCED)
    end
  end
end
