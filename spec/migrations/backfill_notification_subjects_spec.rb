require 'rails_helper'
require 'securerandom'
require Rails.root.join('db/migrate/20260612130000_backfill_notification_subjects_and_resolution.rb').to_s

# Correctness spec for the one-time backfill that links legacy notification
# rows (subject NULL, resolved_at NULL) to their obligation objects and
# resolves the ones whose obligation is already done. The migration is
# self-contained (inline derivation, no registry/Resolver calls), so these
# specs exercise the migration's own logic, not the live resolution path.
RSpec.describe BackfillNotificationSubjectsAndResolution, type: :model, skip_hooks: true do
  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  def create_user(prefix)
    User.create!(user_name: "#{prefix}-#{SecureRandom.hex(3)}", password: 'password123')
  end

  # Runs the migration's up, swallowing its `puts` deploy-record line.
  def run_migration!
    original_stdout = $stdout
    $stdout = StringIO.new
    described_class.new.up
  ensure
    $stdout = original_stdout
  end

  # Legacy-shaped row: subject and resolution columns all NULL, exactly as
  # every pre-feature notification looks before the backfill runs.
  def create_legacy_notification(recipient:, type:, target_type:, target_id:, metadata: {})
    Notification.create!(
      recipient:         recipient,
      notification_type: type,
      message:           'legacy notification',
      target_type:       target_type,
      target_id:         target_id,
      metadata:          metadata
    )
  end

  describe 'request_created backfill' do
    let(:buyer)    { create_user('buyer') }
    let(:seller_a) { create_user('seller-a') }
    let(:seller_b) { create_user('seller-b') }

    let(:grade)     { Grade.create!(name: 'A', value: 30) }
    let(:item_unit) { ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592) }
    let(:category)  { Category.create!(category_name: 'greens', default_unit: item_unit, kind: :produce, default_node_price: 1.0) }
    let(:item_name) { ItemName.create!(name: 'Tomatoes', category: category) }
    let(:item) do
      Item.create!(
        user: seller_b, category: category, item_name: item_name,
        grade: grade, item_unit: item_unit, name: 'Tomatoes', price: 5.0, quantity: 100
      )
    end
    let(:inventory) do
      Inventory.create!(user: seller_b, item: item, quantity: 100, price: 5, status: :available)
    end
    let(:contract) do
      RequestContract.create!(user: buyer, item: item, inventory_id: inventory.id, quantity: 10, steps: 2)
    end

    context 'fixture 1 — partially-accepted multi-hop chain' do
      let!(:hop_a) do
        ItemRequest.create!(
          user: buyer, friend: seller_a, request_contract: contract,
          price: 5, status: :accepted, step: 1
        )
      end
      let!(:hop_b) do
        ItemRequest.create!(
          user: seller_a, friend: seller_b, request_contract: contract,
          price: 5, status: :pending, step: 2
        )
      end
      let!(:notification_a) do
        create_legacy_notification(
          recipient: seller_a, type: 'request_created',
          target_type: 'item', target_id: inventory.id,
          metadata: { 'request_contract_id' => contract.id }
        )
      end
      let!(:notification_b) do
        create_legacy_notification(
          recipient: seller_b, type: 'request_created',
          target_type: 'item', target_id: inventory.id,
          metadata: { 'request_contract_id' => contract.id }
        )
      end

      it "resolves the accepted hop as 'accepted' and links it" do
        run_migration!

        notification_a.reload
        expect(notification_a.subject_type).to eq('ItemRequest')
        expect(notification_a.subject_id).to eq(hop_a.id)
        expect(notification_a.resolved_at).to be_present
        expect(notification_a.resolution_reason).to eq('accepted')
      end

      it 'links the still-pending hop but leaves it live' do
        run_migration!

        notification_b.reload
        expect(notification_b.subject_type).to eq('ItemRequest')
        expect(notification_b.subject_id).to eq(hop_b.id)
        expect(notification_b.resolved_at).to be_nil
        expect(notification_b.resolution_reason).to be_nil
      end
    end

    context 'fixture 3 — orphaned contract (source object deleted)' do
      let!(:orphan_notification) do
        create_legacy_notification(
          recipient: seller_a, type: 'request_created',
          target_type: 'item', target_id: 0,
          metadata: { 'request_contract_id' => 999_999 }
        )
      end

      it "resolves as 'orphaned' without linking a subject" do
        run_migration!

        orphan_notification.reload
        expect(orphan_notification.subject_type).to be_nil
        expect(orphan_notification.subject_id).to be_nil
        expect(orphan_notification.resolved_at).to be_present
        expect(orphan_notification.resolution_reason).to eq('orphaned')
      end
    end
  end

  describe 'payment events backfill' do
    let(:payer) { create_user('payer') }
    let(:payee) { create_user('payee') }
    let(:trustline) do
      a, b = [payer, payee].sort_by(&:id)
      Trustline.create!(
        user_a: a, user_b: b,
        credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0
      )
    end

    context 'fixture 2 — trustline with two open payments (ambiguous match)' do
      let!(:payment_one) do
        PendingPayment.create!(
          from_user: payer, to_user: payee, trustline: trustline,
          amount: 25.0, kind: :payment, status: :pending
        )
      end
      let!(:payment_two) do
        PendingPayment.create!(
          from_user: payer, to_user: payee, trustline: trustline,
          amount: 40.0, kind: :payment, status: :pending
        )
      end
      let!(:notification) do
        create_legacy_notification(
          recipient: payee, type: 'pending_payment_created',
          target_type: 'trustline', target_id: trustline.id
        )
      end

      it "resolves as 'resolved_elsewhere' instead of guess-linking" do
        run_migration!

        notification.reload
        expect(notification.subject_type).to be_nil
        expect(notification.subject_id).to be_nil
        expect(notification.resolved_at).to be_present
        expect(notification.resolution_reason).to eq('resolved_elsewhere')
      end
    end
  end
end
