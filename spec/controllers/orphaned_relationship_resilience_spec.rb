require 'rails_helper'

# Regression: a relationship whose counterparty was hard-deleted leaves a dangling
# friend_id (friend_id has NO foreign key, unlike user_id). That used to nil out the
# friend in contact_list and raise RecordNotFound in items#index, 500-ing the whole
# contact book / dashboard over one stale row. (Prod incident: a user kept a
# relationship pointing at a since-deleted demo account.)
#
# Self-sufficient — builds its own users via the factory rather than relying on a
# demo-network seed (the slim seed only creates admin/robin).
module OrphanRelHelper
  def make_user(name)
    create(:user, user_name: name, email: "#{name}@test.com")
  end

  # Create a healthy relationship + an orphaned one, then delete the orphan's
  # friend so friend_id dangles (friend_id has no FK). Returns the now-missing id.
  def build_orphaned_relationship(me, healthy)
    Relationship.create!(user: me, friend: healthy, status: 1, action_user_id: me.id)
    ghost = make_user('orphan_ghost')
    Relationship.create!(user: me, friend: ghost, status: 1, action_user_id: me.id)
    missing_id = ghost.id
    ghost.delete # raw delete: no callbacks, and friend_id has no FK, so the row dangles
    missing_id
  end

  def stub_current_user(controller, user)
    allow(controller).to receive(:authenticate!).and_return(true)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end
end

RSpec.describe Api::V1::UsersController, type: :controller do
  include OrphanRelHelper

  let(:me)      { make_user('orphan_me') }
  let(:healthy) { make_user('orphan_friend') }

  before(:each) do
    @missing_id = build_orphaned_relationship(me, healthy)
    stub_current_user(controller, me)
  end

  describe '#contact_list' do
    it 'loads without choking on a relationship to a deleted user' do
      get :contact_list
      expect(response).to be_successful
      ids = JSON(response.body)['items'].flat_map { |r| [r.dig('user', 'id'), r.dig('friend', 'id')] }
      expect(ids).to include(healthy.id)      # healthy contact still returned
      expect(ids).not_to include(@missing_id) # orphaned relationship skipped
    end
  end
end

RSpec.describe Api::V1::ItemsController, type: :controller do
  include OrphanRelHelper

  let(:me)      { make_user('orphan_me') }
  let(:healthy) { make_user('orphan_friend') }

  before(:each) do
    build_orphaned_relationship(me, healthy)
    stub_current_user(controller, me)
  end

  describe '#index' do
    it 'loads the dashboard without RecordNotFound on the deleted counterparty' do
      expect {
        get :index, params: { range_degree: 1, dashboard_type: 'consumer' }
      }.not_to raise_error
      expect(response).to be_successful
    end
  end
end
