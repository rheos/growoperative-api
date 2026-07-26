require "rails_helper"

RSpec.describe Foaf::LimitWriteReceipt, skip_hooks: true do
  let(:viewer) do
    User.create!(user_name: "limit-viewer", password: "password123")
  end
  let(:counterparty) do
    User.create!(user_name: "limit-other", password: "password123")
  end
  let(:trustline) do
    Trustline.create!(
      user_a: viewer,
      user_b: counterparty,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 200,
      current_balance: 999
    )
  end
  let(:serializer) { ->(row) { row.slice(:viewer_balance, :my_credit_limit) } }

  before do
    DatabaseCleaner.clean_with(:truncation)
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  it "returns operation state plus only the FOAF-refetched balance state" do
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    entry.update!(
      foaf_posted_at: Time.current,
      foaf_write_state: "posted"
    )
    allow(Foaf::BalanceReader).to receive(:fetch).with(viewer).and_return([
      {
        trustline: trustline,
        counterparty: counterparty,
        viewer_balance: 12.5,
        my_credit_limit: 120
      }
    ])

    result = described_class.build(
      entry: entry,
      trustline: trustline,
      viewer: viewer,
      message: "Trustline updated",
      success_status: :ok,
      serializer: serializer
    )

    expect(result.status).to eq(:ok)
    expect(result.body[:operation]).to include(
      buffer_id: entry.id,
      write_state: "posted"
    )
    expect(result.body[:foaf_state]).to eq(
      viewer_balance: 12.5,
      my_credit_limit: 120
    )
    expect(result.body.to_s).not_to include("999")
  end

  it "returns 202 with no Rails fallback when the write remains buffered" do
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    entry.update!(foaf_write_state: "ambiguous_accept")
    allow(Foaf::BalanceReader).to receive(:fetch).and_return(nil)

    result = described_class.build(
      entry: entry,
      trustline: trustline,
      viewer: viewer,
      message: "Trustline created",
      success_status: :created,
      serializer: serializer
    )

    expect(result.status).to eq(:accepted)
    expect(result.body[:operation][:write_state]).to eq("ambiguous_accept")
    expect(result.body[:foaf_state]).to be_nil
    expect(result.body[:refetch_error]).to be_present
  end
end
