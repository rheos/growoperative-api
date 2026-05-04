require 'rails_helper'

RSpec.describe Api::V1::TrustlinesController, type: :controller, skip_hooks: true do
  before do
    DatabaseCleaner.strategy = :deletion
    DatabaseCleaner.clean_with(:truncation)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe 'GET #index' do
    it "uses the viewer's relationship label for the counterparty name" do
      bruce = User.create!(
        user_name: 'bruce-trustline-label',
        email: 'bruce-trustline-label@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000b01'
      )
      alex = User.create!(
        user_name: 'alexandremayer22@gmail.com',
        email: 'alex-trustline-label@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000a01'
      )
      trustline = Trustline.create!(
        user_a: bruce,
        user_b: alex,
        credit_limit_a_to_b: 100,
        credit_limit_b_to_a: 225,
        current_balance: -128
      )
      Relationship.create!(
        user: bruce,
        friend: alex,
        status: :accepted,
        user_label: 'Alex',
        friend_label: 'Bruce'
      )

      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(bruce)
      allow(Foaf::BalanceReader).to receive(:fetch).with(bruce).and_return([
        {
          trustline: trustline,
          counterparty: alex,
          viewer_balance: -128.to_d,
          my_credit_limit: 100.to_d,
          their_credit_limit: 225.to_d
        }
      ])

      get :index

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig(0, 'other_user', 'name')).to eq('Alex')
    end
  end
end
