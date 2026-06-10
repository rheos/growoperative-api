require 'rails_helper'

RSpec.describe Invitation, type: :model, skip_hooks: true do
  let(:password) { 'bobsentme!' }
  let(:creator) { User.create!(user_name: 'inv_creator', password: password) }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe 'multi-use flags' do
    it 'defaults to single-use (multi_use false) and active (disabled_at nil)' do
      inv = creator.invitations.create!(user_type: 'consumer', status: 0)
      expect(inv.multi_use?).to eq(false)
      expect(inv.active?).to eq(true)
      expect(inv.disabled_at).to be_nil
    end

    it 'reports multi_use? when the flag is set' do
      inv = creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true)
      expect(inv.multi_use?).to eq(true)
    end

    it 'reports active? false once disabled_at is set' do
      inv = creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true, disabled_at: Time.current)
      expect(inv.active?).to eq(false)
    end
  end

  describe '#generate_invitation_code' do
    # The fix moved charset sampling INSIDE the begin/end-while retry loop, so a
    # collision retries with a fresh candidate instead of re-checking the same
    # string forever. Stubbing exists? to be true on the first call forces one
    # retry; the loop must then produce a different (second-sample) string.
    it 'samples a fresh code on retry when the first candidate collides' do
      inv = Invitation.new(user: creator, user_type: 'consumer', status: 0)

      first_candidate = nil
      call_count = 0
      allow(Invitation).to receive(:exists?) do |args|
        call_count += 1
        if call_count == 1
          first_candidate = args[:invitation_code]
          true   # first candidate "already exists" -> force a retry
        else
          false  # second candidate is free
        end
      end

      inv.generate_invitation_code

      expect(call_count).to be >= 2
      expect(inv.invitation_code).to be_present
      expect(inv.invitation_code).not_to eq(first_candidate)
    end

    it 'does not overwrite an invitation_code that is already present (FOAF-supplied path)' do
      preset = 'MAVOLENI'
      inv = Invitation.new(user: creator, user_type: 'consumer', status: 0, invitation_code: preset)

      # Guard must short-circuit before any uniqueness check runs.
      expect(Invitation).not_to receive(:exists?)

      inv.generate_invitation_code

      expect(inv.invitation_code).to eq(preset)
    end
  end

  describe 'FOAF reconciliation state constants' do
    it 'exposes the four state values as frozen strings' do
      expect(Invitation::FOAF_STATE_UNSYNCED).to eq('unsynced')
      expect(Invitation::FOAF_STATE_SYNCED).to eq('synced')
      expect(Invitation::FOAF_STATE_FAILED).to eq('failed')
      expect(Invitation::FOAF_STATE_RECONCILED).to eq('reconciled')
      [Invitation::FOAF_STATE_UNSYNCED, Invitation::FOAF_STATE_SYNCED,
       Invitation::FOAF_STATE_FAILED, Invitation::FOAF_STATE_RECONCILED].each do |v|
        expect(v).to be_frozen
      end
    end
  end

  describe 'redemption associations' do
    let(:invitation) { creator.invitations.create!(user_type: 'consumer', status: 0, multi_use: true) }
    let(:redeemer) { User.create!(user_name: 'inv_redeemer', password: password) }

    it 'has many redemptions and redeemers through them' do
      invitation.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
      expect(invitation.invitation_redemptions.count).to eq(1)
      expect(invitation.redeemers).to include(redeemer)
    end

    it 'destroys redemptions when the invitation is destroyed' do
      invitation.invitation_redemptions.create!(user_id: redeemer.id, redeemed_at: Time.current)
      expect { invitation.destroy }.to change(InvitationRedemption, :count).by(-1)
    end
  end
end
