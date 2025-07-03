# Social Graph Relationship Storage Migration

## Overview

This document outlines the migration from the current directional relationship model to a symmetric junction table approach, eliminating directional confusion and improving query performance.

## Current Problems

### 1. Directional Confusion
- Relationships stored as `user_id` → `friend_id` pairs
- Current user can be either `user` or `friend` in the relationship
- Complex logic required to find contacts: check both directions
- Frontend has to handle bidirectional relationship detection

### 2. Data Complexity
```ruby
# Current problematic logic in frontend
if (relation.user.id === currentUser.id) {
  contactUser = relation.friend
  contactLabel = relation.friend_label
} else {
  contactUser = relation.user  
  contactLabel = relation.user_label
}
```

### 3. Query Performance
- Multiple joins required to find all user contacts
- Cannot efficiently index bidirectional relationships
- Complex WHERE clauses: `WHERE user_id = ? OR friend_id = ?`

## Proposed Solution: Symmetric Junction Table

### Database Schema Changes

#### New Tables
```ruby
# db/migrate/xxxx_create_symmetric_relationships.rb
class CreateSymmetricRelationships < ActiveRecord::Migration[7.0]
  def change
    create_table :user_relationships do |t|
      t.bigint :user_a_id, null: false  # Always the lower ID
      t.bigint :user_b_id, null: false  # Always the higher ID
      t.string :status, default: 'pending' # pending, accepted, blocked
      t.bigint :initiated_by_id, null: false
      t.string :user_a_label # Custom label user_a gave to user_b
      t.string :user_b_label # Custom label user_b gave to user_a
      t.integer :actions_state_a, default: 0
      t.integer :actions_state_b, default: 0
      
      t.timestamps
      
      # Ensure user_a_id < user_b_id for consistency
      t.check_constraint 'user_a_id < user_b_id', name: 'user_order_check'
      t.index [:user_a_id, :user_b_id], unique: true, name: 'unique_relationship'
      t.index [:user_a_id, :status]
      t.index [:user_b_id, :status]
      t.index :initiated_by_id
    end
    
    add_foreign_key :user_relationships, :users, column: :user_a_id
    add_foreign_key :user_relationships, :users, column: :user_b_id  
    add_foreign_key :user_relationships, :users, column: :initiated_by_id
  end
end

# db/migrate/xxxx_create_relationship_prices.rb  
class CreateRelationshipPrices < ActiveRecord::Migration[7.0]
  def change
    create_table :relationship_prices do |t|
      t.references :user_relationship, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.decimal :price_a_to_b, precision: 10, scale: 2 # When user_a sells to user_b
      t.decimal :price_b_to_a, precision: 10, scale: 2 # When user_b sells to user_a
      t.decimal :markup_a_to_b, precision: 5, scale: 2
      t.decimal :markup_b_to_a, precision: 5, scale: 2
      t.string :receiving_price_type_a
      t.string :receiving_price_type_b
      
      t.timestamps
      
      t.index [:user_relationship_id, :category_id], unique: true
    end
  end
end
```

### Model Updates

#### New Models
```ruby
# app/models/user_relationship.rb
class UserRelationship < ApplicationRecord
  belongs_to :user_a, class_name: 'User'
  belongs_to :user_b, class_name: 'User'
  belongs_to :initiated_by, class_name: 'User'
  
  has_many :relationship_prices, dependent: :destroy
  
  validates :status, inclusion: { in: %w[pending accepted blocked] }
  validate :user_order_validation
  
  scope :accepted, -> { where(status: 'accepted') }
  scope :pending, -> { where(status: 'pending') }
  scope :for_user, ->(user_id) { where('user_a_id = ? OR user_b_id = ?', user_id, user_id) }
  
  # Find or create relationship ensuring user_a_id < user_b_id
  def self.find_or_initialize_relationship(user1_id, user2_id)
    user_a_id, user_b_id = [user1_id, user2_id].map(&:to_i).sort
    find_or_initialize_by(user_a_id: user_a_id, user_b_id: user_b_id)
  end
  
  # Get the other user in the relationship
  def other_user(current_user_id)
    current_user_id.to_i == user_a_id ? user_b : user_a
  end
  
  # Get the current user's label for the other user
  def label_for_other_user(current_user_id)
    current_user_id.to_i == user_a_id ? user_a_label : user_b_label
  end
  
  # Get the other user's label for current user  
  def label_from_other_user(current_user_id)
    current_user_id.to_i == user_a_id ? user_b_label : user_a_label
  end
  
  # Check if user is user_a
  def user_is_a?(user_id)
    user_a_id == user_id.to_i
  end
  
  private
  
  def user_order_validation
    errors.add(:user_b_id, 'must be greater than user_a_id') if user_a_id >= user_b_id
  end
end

# app/models/relationship_price.rb
class RelationshipPrice < ApplicationRecord
  belongs_to :user_relationship
  belongs_to :category
  
  validates :user_relationship_id, uniqueness: { scope: :category_id }
  
  # Get price when specific user is selling
  def price_for_seller(seller_user_id)
    if user_relationship.user_is_a?(seller_user_id)
      price_a_to_b
    else
      price_b_to_a
    end
  end
  
  # Get markup when specific user is selling
  def markup_for_seller(seller_user_id)
    if user_relationship.user_is_a?(seller_user_id)
      markup_a_to_b
    else
      markup_b_to_a
    end
  end
end
```

#### User Model Updates
```ruby
# app/models/user.rb (add these methods)
class User < ApplicationRecord
  # ... existing code ...
  
  has_many :relationships_as_a, class_name: 'UserRelationship', foreign_key: 'user_a_id'
  has_many :relationships_as_b, class_name: 'UserRelationship', foreign_key: 'user_b_id'
  has_many :initiated_relationships, class_name: 'UserRelationship', foreign_key: 'initiated_by_id'
  
  # Get all relationships for this user
  def user_relationships
    UserRelationship.for_user(id)
  end
  
  # Get all accepted contacts
  def contacts
    user_relationships.accepted.includes(:user_a, :user_b)
  end
  
  # Get contact users with metadata
  def contacts_with_metadata
    contacts.map do |relationship|
      other_user = relationship.other_user(id)
      {
        user: other_user,
        relationship: relationship,
        label: relationship.label_for_other_user(id),
        since: relationship.created_at
      }
    end
  end
  
  # Find relationship with another user
  def relationship_with(other_user_id)
    UserRelationship.find_or_initialize_relationship(id, other_user_id)
  end
  
  # Check if connected to another user
  def connected_to?(other_user_id)
    relationship_with(other_user_id).status == 'accepted'
  end
end
```

### API Controller Updates

#### New Contacts Controller
```ruby
# app/controllers/api/v1/contacts_controller.rb
class Api::V1::ContactsController < Api::V1::ApiController
  before_action :authenticate_api_user!
  
  # GET /api/v1/contacts
  def index
    contacts = current_user.contacts_with_metadata
    
    # Include relationship prices if item_id provided (for reserve form)
    if params[:item_id].present?
      item = current_user.items.find(params[:item_id])
      contacts = contacts.map do |contact_data|
        relationship = contact_data[:relationship] 
        price_data = relationship.relationship_prices
                                 .joins(:category)
                                 .find_by(categories: { id: item.category_id })
        
        contact_data.merge({
          relationship_price: price_data&.price_for_seller(current_user.id) || 0,
          markup: price_data&.markup_for_seller(current_user.id) || 0
        })
      end
    end
    
    render json: {
      items: contacts.map { |contact| serialize_contact(contact) },
      default_markup: GlobalSetting.find_by(name: 'default_markup')&.value || '1.0'
    }
  end
  
  # POST /api/v1/contacts
  def create
    other_user = User.find_by(invitation_code: params[:invitation_code])
    return render_error('Invalid invitation code') unless other_user
    
    relationship = current_user.relationship_with(other_user.id)
    
    if relationship.persisted?
      return render_error('Relationship already exists')
    end
    
    relationship.assign_attributes(
      initiated_by: current_user,
      status: 'pending',
      user_a_label: params[:label]
    )
    
    if relationship.save
      # Send notification to other user
      # NotificationService.send_connection_request(other_user, current_user)
      render json: { message: 'Connection request sent' }
    else
      render_error(relationship.errors.full_messages.join(', '))
    end
  end
  
  # PATCH /api/v1/contacts/:id
  def update
    relationship = current_user.user_relationships.find(params[:id])
    
    case params[:action_type]
    when 'accept'
      relationship.update!(status: 'accepted')
      render json: { message: 'Connection accepted' }
    when 'reject'
      relationship.update!(status: 'blocked') 
      render json: { message: 'Connection rejected' }
    when 'update_label'
      label_field = relationship.user_is_a?(current_user.id) ? :user_a_label : :user_b_label
      relationship.update!(label_field => params[:label])
      render json: { message: 'Label updated' }
    else
      render_error('Invalid action')
    end
  end
  
  private
  
  def serialize_contact(contact_data)
    {
      id: contact_data[:relationship].id,
      friend_id: contact_data[:user].id,
      status: contact_data[:relationship].status,
      user_label: contact_data[:label],
      friend_label: contact_data[:relationship].label_from_other_user(current_user.id),
      user: serialize_user(current_user),
      friend: serialize_user(contact_data[:user]),
      relationship_price: contact_data[:relationship_price],
      markup: contact_data[:markup],
      since: contact_data[:since]
    }
  end
  
  def serialize_user(user)
    {
      id: user.id,
      user_name: user.user_name,
      nickname: user.nickname,
      name: user.name,
      email: user.email,
      user_groups: user.user_groups.map { |ug| { group_label: ug.group_label } }
    }
  end
  
  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
```

### Migration Strategy

#### Data Migration Script
```ruby
# db/migrate/xxxx_migrate_existing_relationships.rb
class MigrateExistingRelationships < ActiveRecord::Migration[7.0]
  def up
    # Create mapping of old relationships to new symmetric ones
    old_relationships = execute(<<-SQL)
      SELECT r1.id as id1, r1.user_id as user1, r1.friend_id as friend1,
             r1.status, r1.user_label, r1.friend_label,
             r1.actions_state, r1.friend_actions_state,
             r1.created_at, r1.updated_at,
             r2.id as id2, r2.user_label as user2_label, r2.friend_label as friend2_label,
             r2.actions_state as user2_actions_state, r2.friend_actions_state as friend2_actions_state
      FROM relationships r1
      LEFT JOIN relationships r2 ON r1.user_id = r2.friend_id AND r1.friend_id = r2.user_id
      WHERE r1.user_id < r1.friend_id OR r2.id IS NULL
    SQL
    
    old_relationships.each do |row|
      user_a_id = [row['user1'], row['friend1']].min
      user_b_id = [row['user1'], row['friend1']].max
      
      # Determine who initiated (assuming user1 initiated if no reciprocal)
      initiated_by_id = row['id2'] ? row['user1'] : row['user1']
      
      # Create new symmetric relationship
      new_relationship = UserRelationship.create!(
        user_a_id: user_a_id,
        user_b_id: user_b_id,
        status: row['status'],
        initiated_by_id: initiated_by_id,
        user_a_label: user_a_id == row['user1'] ? row['user_label'] : row['user2_label'],
        user_b_label: user_b_id == row['friend1'] ? row['friend_label'] : row['friend2_label'],
        actions_state_a: user_a_id == row['user1'] ? row['actions_state'] : row['user2_actions_state'],
        actions_state_b: user_b_id == row['friend1'] ? row['friend_actions_state'] : row['friend2_actions_state'],
        created_at: row['created_at'],
        updated_at: row['updated_at']
      )
      
      # Migrate relationship prices
      old_prices = execute(<<-SQL)
        SELECT * FROM user_relationship_prices 
        WHERE relationship_id IN (#{row['id1']}#{row['id2'] ? ", #{row['id2']}" : ''})
      SQL
      
      old_prices.group_by { |p| p['category_id'] }.each do |category_id, prices|
        price_a_to_b = nil
        price_b_to_a = nil
        markup_a_to_b = nil
        markup_b_to_a = nil
        
        prices.each do |price|
          if price['user_id'] == user_a_id && price['friend_id'] == user_b_id
            price_a_to_b = price['price']
            markup_a_to_b = price['markup'] || 0
          elsif price['user_id'] == user_b_id && price['friend_id'] == user_a_id
            price_b_to_a = price['price']  
            markup_b_to_a = price['markup'] || 0
          end
        end
        
        RelationshipPrice.create!(
          user_relationship: new_relationship,
          category_id: category_id,
          price_a_to_b: price_a_to_b,
          price_b_to_a: price_b_to_a,
          markup_a_to_b: markup_a_to_b,
          markup_b_to_a: markup_b_to_a
        )
      end
    end
  end
  
  def down
    # Rollback migration if needed
    UserRelationship.delete_all
    RelationshipPrice.delete_all
  end
end
```

### Frontend Updates

#### Simplified Contact Processing
```javascript
// New simplified logic in ReserveItemForm.js
useEffect(() => {
  if (reduxContacts?.items?.length) {
    const processedContacts = reduxContacts.items.map(contact => ({
      name: contact.user_label || contact.friend.nickname || contact.friend.user_name,
      id: contact.friend.id,
      relationshipPrice: Number(contact.relationship_price) || 0
    }));

    setContacts(processedContacts);
    // ... rest of logic
  }
}, [reduxContacts]);
```

## Implementation Timeline

### Phase 1: Database Setup (Week 1)
- [ ] Create new table migrations
- [ ] Add new models with tests
- [ ] Create data migration script
- [ ] Test migration on staging data

### Phase 2: API Updates (Week 2)  
- [ ] Create new contacts controller
- [ ] Update existing endpoints to use new models
- [ ] Maintain backward compatibility
- [ ] Add comprehensive tests

### Phase 3: Frontend Integration (Week 3)
- [ ] Update ReserveItemForm to use new API
- [ ] Update contact management components
- [ ] Test all relationship flows
- [ ] Performance testing

### Phase 4: Cleanup (Week 4)
- [ ] Remove old relationship models/controllers
- [ ] Drop old database tables
- [ ] Update documentation
- [ ] Performance monitoring

## Testing Strategy

### Unit Tests
```ruby
# spec/models/user_relationship_spec.rb
RSpec.describe UserRelationship, type: :model do
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  
  describe '.find_or_initialize_relationship' do
    it 'orders users correctly' do
      relationship = UserRelationship.find_or_initialize_relationship(user2.id, user1.id)
      expect(relationship.user_a_id).to eq([user1.id, user2.id].min)
      expect(relationship.user_b_id).to eq([user1.id, user2.id].max)
    end
  end
  
  describe '#other_user' do
    let(:relationship) { create(:user_relationship, user_a: user1, user_b: user2) }
    
    it 'returns correct other user' do
      expect(relationship.other_user(user1.id)).to eq(user2)
      expect(relationship.other_user(user2.id)).to eq(user1)
    end
  end
end
```

### Integration Tests  
```ruby
# spec/requests/api/v1/contacts_spec.rb
RSpec.describe 'Contacts API', type: :request do
  let(:user) { create(:user) }
  let(:contact) { create(:user) }
  let!(:relationship) { create(:user_relationship, user_a: user, user_b: contact, status: 'accepted') }
  
  describe 'GET /api/v1/contacts' do
    it 'returns user contacts' do
      get '/api/v1/contacts', headers: auth_headers(user)
      
      expect(response).to have_http_status(:ok)
      expect(json_response['items']).to have(1).item
      expect(json_response['items'][0]['friend']['user_name']).to eq(contact.user_name)
    end
  end
end
```

## Performance Considerations

### Database Indexes
```sql
-- Critical indexes for performance
CREATE INDEX idx_user_relationships_user_a_status ON user_relationships(user_a_id, status);
CREATE INDEX idx_user_relationships_user_b_status ON user_relationships(user_b_id, status);
CREATE INDEX idx_relationship_prices_lookup ON relationship_prices(user_relationship_id, category_id);
```

### Query Optimization
```ruby
# Efficient contact loading with includes
def contacts_for_item(user_id, item_id)
  item = Item.find(item_id)
  
  UserRelationship.accepted
                  .for_user(user_id)
                  .includes(:user_a, :user_b, 
                           relationship_prices: :category)
                  .where(relationship_prices: { category_id: item.category_id })
end
```

## Benefits After Migration

1. **✅ Simplified Logic**: No more directional checking
2. **✅ Better Performance**: Optimized queries and indexes  
3. **✅ Data Integrity**: Single source of truth per relationship
4. **✅ Easier Maintenance**: Cleaner codebase
5. **✅ Scalability**: Efficient for large networks

## Rollback Plan

If issues arise:
1. Keep old tables during transition period
2. Feature flags to switch between old/new systems
3. Data validation scripts to ensure consistency
4. Automated rollback procedures

---

*This migration will resolve the directional confusion issue permanently and provide a solid foundation for future social graph features.* 