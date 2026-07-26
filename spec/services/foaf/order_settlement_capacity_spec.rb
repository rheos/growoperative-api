require "rails_helper"

RSpec.describe Foaf::OrderSettlementCapacity, skip_hooks: true do
  let(:buyer) do
    User.create!(
      user_name: "capacity-buyer",
      email: "capacity-buyer@example.com",
      password: "password123",
      foaf_address: "0x0000000000000000000000000000000000000a31"
    )
  end
  let(:seller) do
    User.create!(
      user_name: "capacity-seller",
      email: "capacity-seller@example.com",
      password: "password123",
      foaf_address: "0x0000000000000000000000000000000000000b31"
    )
  end
  let(:capacity_reader) { class_double(Foaf::DirectCapacityReader) }
  let(:balance_reader) { class_double(Foaf::BalanceReader) }

  before do
    DatabaseCleaner.clean_with(:truncation)
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::LedgerHooks).to receive(:after_trustline_save)
    allow(balance_reader).to receive(:fetch)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  def capacity(value, error: nil)
    Foaf::DirectCapacityReader::Result.new(
      capacity: BigDecimal(value.to_s),
      error: error
    )
  end

  def ensure_capacity(amount: "25")
    described_class.ensure!(
      from_user: buyer,
      to_user: seller,
      amount: amount,
      capacity_reader: capacity_reader,
      balance_reader: balance_reader
    )
  end

  it "uses an already-sufficient FOAF capacity without reading Rails balance math" do
    trustline = Trustline.create!(
      user_a: buyer,
      user_b: seller,
      credit_limit_a_to_b: 5,
      credit_limit_b_to_a: 5,
      current_balance: 999,
      is_active: true
    )
    allow(capacity_reader).to receive(:fetch).and_return(capacity("25"))
    expect(balance_reader).not_to receive(:fetch)
    expect(trustline).not_to receive(:available_credit_for)

    expect(ensure_capacity).to eq(trustline)
    expect(Foaf::LedgerHooks).not_to have_received(:after_trustline_save)
  end

  it "expands by the whole-unit FOAF shortfall and verifies again" do
    trustline = Trustline.create!(
      user_a: buyer,
      user_b: seller,
      credit_limit_a_to_b: 999,
      credit_limit_b_to_a: 5,
      current_balance: 888,
      is_active: true
    )
    allow(capacity_reader).to receive(:fetch).and_return(
      capacity("7"),
      capacity("25")
    )
    allow(balance_reader).to receive(:fetch).with(buyer).and_return([
      {
        trustline: trustline,
        counterparty: seller,
        viewer_balance: 700,
        my_credit_limit: BigDecimal("40"),
        their_credit_limit: 5
      }
    ])

    ensure_capacity

    trustline.reload
    expected_limit = BigDecimal("58")
    actual_limit = trustline.credit_limit_for(buyer)
    expect(actual_limit).to eq(expected_limit)
    expect(Foaf::LedgerHooks).to have_received(:after_trustline_save)
      .with(trustline, buyer).once
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    expect(entry.credit_limit_a_to_b).to eq(
      buyer.id == trustline.user_a_id ? expected_limit : BigDecimal("5")
    )
    expect(entry.credit_limit_b_to_a).to eq(
      buyer.id == trustline.user_b_id ? expected_limit : BigDecimal("5")
    )
  end

  it "rounds a fractional protocol-reported shortfall up to the next capacity unit" do
    trustline = Trustline.create!(
      user_a: buyer,
      user_b: seller,
      credit_limit_a_to_b: BigDecimal("3.45"),
      credit_limit_b_to_a: 0,
      current_balance: 0,
      is_active: true
    )
    allow(capacity_reader).to receive(:fetch).and_return(
      capacity("3"),
      capacity("3"),
      capacity("3"),
      capacity("4")
    )
    allow(balance_reader).to receive(:fetch).and_return([
      {
        trustline: trustline,
        counterparty: seller,
        viewer_balance: 0,
        my_credit_limit: BigDecimal("3.45"),
        their_credit_limit: 0
      }
    ])

    ensure_capacity(amount: "3.45")

    expect(trustline.reload.credit_limit_for(buyer)).to eq(BigDecimal("4.45"))
  end

  it "polls read-only capacity after publishing a new limit" do
    allow(capacity_reader).to receive(:fetch).and_return(
      capacity("0", error: "FOAF capacity unavailable"),
      capacity("0"),
      capacity("25")
    )

    trustline = ensure_capacity

    expect(trustline).to be_persisted
    expect(capacity_reader).to have_received(:fetch).exactly(3).times
    expect(balance_reader).not_to have_received(:fetch)
  end

  it "creates relationship metadata, retains its durable limit snapshot, and verifies FOAF" do
    allow(capacity_reader).to receive(:fetch).and_return(capacity("25"))

    trustline = ensure_capacity

    expect(trustline).to be_persisted
    expect(trustline.credit_limit_for(buyer)).to eq(BigDecimal("25"))
    expect(FoafOutboxEntry.latest_trustline_update_for(trustline)).to be_present
    expect(Foaf::LedgerHooks).to have_received(:after_trustline_save)
      .with(trustline, buyer).once
  end

  it "fails loud and retains the outbox when FOAF cannot verify a new trustline" do
    allow(capacity_reader).to receive(:fetch).and_return(
      capacity("0", error: "FOAF capacity unavailable")
    )

    expect { ensure_capacity }.to raise_error(
      described_class::Error,
      "FOAF capacity unavailable"
    )
    trustline = Trustline.between_users(buyer, seller).first
    expect(trustline).to be_present
    expect(FoafOutboxEntry.latest_trustline_update_for(trustline)).to be_present
  end

  it "does not execute when capacity remains insufficient after publication" do
    trustline = Trustline.create!(
      user_a: buyer,
      user_b: seller,
      credit_limit_a_to_b: 10,
      credit_limit_b_to_a: 10,
      current_balance: 0,
      is_active: true
    )
    allow(capacity_reader).to receive(:fetch).and_return(
      capacity("5"),
      capacity("24.99"),
      capacity("24.99"),
      capacity("24.99")
    )
    allow(balance_reader).to receive(:fetch).and_return([
      {
        trustline: trustline,
        counterparty: seller,
        viewer_balance: 0,
        my_credit_limit: 10,
        their_credit_limit: 10
      }
    ])

    expect { ensure_capacity }.to raise_error(
      described_class::Error,
      "FOAF capacity remained insufficient after the durable limit update"
    )
  end
end
