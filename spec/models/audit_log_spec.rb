require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  describe 'validations' do
    it 'requires an action' do
      expect(AuditLog.new(status: 'succeeded')).not_to be_valid
    end

    it 'rejects an unknown status' do
      log = AuditLog.new(action: 'demo.reset', status: 'whoops')
      expect(log).not_to be_valid
      expect(log.errors[:status]).to be_present
    end
  end

  describe '.record' do
    let(:user) { User.create!(user_name: 'audit_bob', password: 'bobsentme!') }

    it 'creates a row with actor derived from actor_user' do
      log = AuditLog.record(action: 'demo.reset', actor_user: user, source: 'api')
      expect(log).to be_persisted
      expect(log.actor).to eq('audit_bob')
      expect(log.actor_user_id).to eq(user.id)
      expect(log.status).to eq('succeeded')
    end

    it 'defaults actor to "system" when no actor is given' do
      log = AuditLog.record(action: 'demo.reset', source: 'rake')
      expect(log.actor).to eq('system')
    end

    it 'prefers an explicit actor string over the user name' do
      log = AuditLog.record(action: 'demo.reset', actor: 'operator:ubuntu@host', source: 'script')
      expect(log.actor).to eq('operator:ubuntu@host')
    end

    it 'stores metadata' do
      log = AuditLog.record(action: 'demo.reset', metadata: { snapshot_name: 'default' })
      expect(log.reload.metadata['snapshot_name']).to eq('default')
    end

    it 'never raises on failure — returns nil and logs instead' do
      expect(Rails.logger).to receive(:error).with(/AuditLog/)
      expect(AuditLog.record(action: nil)).to be_nil
    end
  end
end
