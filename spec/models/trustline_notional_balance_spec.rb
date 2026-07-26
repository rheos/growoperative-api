require "rails_helper"

RSpec.describe "notional trustline balance helpers", type: :model, skip_hooks: true do
  let!(:alice) do
    User.create!(
      user_name: "notional-alice",
      email: "notional-alice@example.com",
      password: "password123"
    )
  end
  let!(:bob) do
    User.create!(
      user_name: "notional-bob",
      email: "notional-bob@example.com",
      password: "password123"
    )
  end
  let!(:trustline) do
    Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 40,
      current_balance: 25
    )
  end

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  it "labels perspective and capacity calculations as notional" do
    expect(trustline.notional_balance_for(alice)).to eq(25)
    expect(trustline.notional_balance_for(bob)).to eq(-25)
    expect(trustline.notional_available_credit_for(alice)).to eq(75)
    expect(trustline.notional_available_credit_for(bob)).to eq(40)
    expect(trustline.notional_can_handle_payment?(75, alice)).to be(true)
    expect(trustline.notional_can_handle_payment?(76, alice)).to be(false)
  end

  it "labels user aggregates as notional" do
    expect(alice.notional_total_credit_owed).to eq(25)
    expect(alice.notional_total_credit_owed_to_me).to eq(0)
    expect(alice.notional_net_credit_position).to eq(-25)
    expect(alice.notional_available_credit_total).to eq(75)
    expect(alice.notional_can_pay?(75, bob)).to be(true)

    expect(bob.notional_total_credit_owed).to eq(0)
    expect(bob.notional_total_credit_owed_to_me).to eq(25)
    expect(bob.notional_net_credit_position).to eq(25)
  end

  it "does not expose the retired authoritative-sounding helper names" do
    expect(trustline).not_to respond_to(:balance_for)
    expect(trustline).not_to respond_to(:available_credit_for)
    expect(trustline).not_to respond_to(:can_handle_payment?)
    expect(alice).not_to respond_to(:total_credit_owed)
    expect(alice).not_to respond_to(:total_credit_owed_to_me)
    expect(alice).not_to respond_to(:net_credit_position)
    expect(alice).not_to respond_to(:available_credit_total)
    expect(alice).not_to respond_to(:can_pay?)
  end
end
