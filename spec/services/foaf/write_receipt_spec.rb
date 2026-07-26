require "rails_helper"

RSpec.describe Foaf::WriteReceipt, skip_hooks: true do
  before do
    DatabaseCleaner.strategy = :deletion
    DatabaseCleaner.clean_with(:truncation)
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  let(:viewer) do
    User.create!(
      user_name: "write-receipt-viewer",
      email: "write-receipt-viewer@example.com",
      password: "password123",
      foaf_address: "0x0000000000000000000000000000000000000e01"
    )
  end

  let(:counterparty) do
    User.create!(
      user_name: "write-receipt-counterparty",
      email: "write-receipt-counterparty@example.com",
      password: "password123",
      foaf_address: "0x0000000000000000000000000000000000000e02"
    )
  end

  let(:trustline) do
    Trustline.create!(
      user_a: viewer,
      user_b: counterparty,
      credit_limit_a_to_b: 500,
      credit_limit_b_to_a: 400,
      current_balance: 999
    )
  end

  let(:tx_row) do
    trustline.trustline_transactions.create!(
      amount: 10,
      transaction_type: "payment",
      initiated_by: viewer,
      balance_after: 999,
      foaf_direction: "sent"
    )
  end

  let(:foaf_row) do
    {
      trustline: trustline,
      counterparty: counterparty,
      viewer_balance: 12.5,
      my_credit_limit: 500.0,
      their_credit_limit: 400.0
    }
  end

  def build_receipt
    described_class.build(
      tx_row: tx_row,
      viewer: viewer,
      message: "Payment processed successfully"
    )
  end

  it "returns posted operation state and the FOAF balance, never Rails balance fields" do
    tx_row.update!(
      foaf_operation_id: 81,
      foaf_pending_transfer_id: 41,
      foaf_posted_at: Time.current,
      foaf_write_state: "posted"
    )
    allow(Foaf::BalanceReader).to receive(:fetch).with(viewer).and_return([foaf_row])

    receipt = build_receipt

    expect(receipt.status).to eq(:ok)
    expect(receipt.body.dig(:operation, :write_state)).to eq("posted")
    expect(receipt.body.dig(:operation, :idempotency_key))
      .to eq("growoperative:trustline_transaction:#{tx_row.id}")
    expect(receipt.body.dig(:foaf_state, :current_balance)).to eq(12.5)
    expect(receipt.body.dig(:foaf_state, :current_balance)).not_to eq(999)
    expect(receipt.body).not_to have_key(:new_balance)
    expect(receipt.body).not_to have_key(:trustline)
  end

  it "returns an actual 422 rejection with retained FOAF error details" do
    tx_row.update!(
      foaf_write_state: "rejected",
      foaf_write_error: {
        status: 409,
        outcome: "rejected",
        error: "credit limit exceeded"
      }.to_json
    )
    allow(Foaf::BalanceReader).to receive(:fetch).with(viewer).and_return([foaf_row])

    receipt = build_receipt

    expect(receipt.status).to eq(:unprocessable_content)
    expect(receipt.body[:message]).to eq("FOAF rejected the write")
    expect(receipt.body.dig(:operation, :write_error, "status")).to eq(409)
    expect(receipt.body.dig(:operation, :write_error, "outcome")).to eq("rejected")
  end

  it "returns 202 for an ambiguous write that remains in the durable buffer" do
    tx_row.update!(foaf_write_state: "ambiguous_confirm")
    allow(Foaf::BalanceReader).to receive(:fetch).with(viewer).and_return([foaf_row])

    receipt = build_receipt

    expect(receipt.status).to eq(:accepted)
    expect(receipt.body[:message]).to eq("Write buffered pending FOAF reconciliation")
    expect(receipt.body.dig(:operation, :write_state)).to eq("ambiguous_confirm")
  end

  it "reports a failed FOAF refetch explicitly without changing a posted write outcome" do
    tx_row.update!(
      foaf_operation_id: 81,
      foaf_posted_at: Time.current,
      foaf_write_state: "posted"
    )
    allow(Foaf::BalanceReader).to receive(:fetch).with(viewer).and_return(nil)

    receipt = build_receipt

    expect(receipt.status).to eq(:ok)
    expect(receipt.body[:foaf_state]).to be_nil
    expect(receipt.body[:refetch_error]).to eq(
      "Balance data unavailable — FOAF refetch failed"
    )
  end
end
