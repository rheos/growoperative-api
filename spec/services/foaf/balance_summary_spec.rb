require "rails_helper"

RSpec.describe Foaf::BalanceSummary, skip_hooks: true do
  let(:user) { instance_double(User) }

  it "aggregates every summary field from one FOAF-backed fetch" do
    rows = [
      { viewer_balance: 30.to_d, my_credit_limit: 100.to_d },
      { viewer_balance: -45.to_d, my_credit_limit: 80.to_d },
      { viewer_balance: 0.to_d, my_credit_limit: 25.to_d }
    ]
    expect(Foaf::BalanceReader).to receive(:fetch).once.with(user).and_return(rows)

    expect(described_class.fetch(user)).to eq(
      total_trustlines: 3,
      total_credit_owed: 30.to_d,
      total_credit_owed_to_me: 45.to_d,
      net_credit_position: 15.to_d,
      available_credit: 175.to_d
    )
  end

  it "returns nil instead of falling back to Rails when FOAF is unavailable" do
    expect(Foaf::BalanceReader).to receive(:fetch).once.with(user).and_return(nil)

    expect(described_class.fetch(user)).to be_nil
  end
end
