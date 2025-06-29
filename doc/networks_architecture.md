# Networks Architecture - Multi-Community Mutual Credit System

## Overview

This document outlines the architecture for implementing **network organization** within the mutual credit system to support multiple independent communities that can eventually interconnect through bridge users.

## Table of Contents

- [Background & Rationale](#background--rationale)
- [Database Schema](#database-schema)
- [Core Models](#core-models)
- [API Enhancements](#api-enhancements)
- [Rollout Strategy](#rollout-strategy)
- [Implementation Phases](#implementation-phases)
- [Benefits & Considerations](#benefits--considerations)
- [Migration Guide](#migration-guide)

## Background & Rationale

### Current Limitation

The existing mutual credit system treats all users as part of one unified global network. While this maximizes network effects, it doesn't align with the planned rollout strategy of:

1. **Seed users** deployed in different geographic areas
2. **Invitation chains** creating naturally isolated communities
3. **Gradual interconnection** as communities mature and form cross-regional relationships

### The Networks Solution

A **networks table** provides organizational structure that:
- Enables multiple independent communities to coexist
- Supports organic growth from seed users through invitation chains
- Maintains performance by limiting path-finding to relevant network subsets
- Allows gradual cross-network integration through bridge users
- Provides network-specific governance and analytics

## Database Schema

### New Tables

#### networks
Stores information about each community network.

```sql
CREATE TABLE networks (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  -- Basic network information
  name VARCHAR(255) NOT NULL,
  description TEXT,
  network_type VARCHAR(50) DEFAULT 'geographic',
  
  -- Network governance
  seed_user_id BIGINT NOT NULL,
  
  -- Network-specific settings
  max_chain_limit INTEGER DEFAULT 5,
  default_invitation_limit INTEGER DEFAULT 10,
  allow_cross_network_payments BOOLEAN DEFAULT false,
  cross_network_max_hops INTEGER DEFAULT 2,
  
  -- Status and metadata
  is_active BOOLEAN DEFAULT true,
  launched_at DATETIME,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  
  -- Indexes
  INDEX index_networks_on_seed_user_id (seed_user_id),
  INDEX index_networks_on_is_active (is_active),
  INDEX index_networks_on_network_type (network_type),
  INDEX index_networks_on_launched_at (launched_at),
  
  -- Foreign keys
  FOREIGN KEY (seed_user_id) REFERENCES users(id)
);
```

#### user_network_memberships
Tracks which users belong to which networks (many-to-many relationship).

```sql
CREATE TABLE user_network_memberships (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  -- Core membership data
  user_id BIGINT NOT NULL,
  network_id BIGINT NOT NULL,
  
  -- Membership metadata
  joined_via_invitation_id BIGINT,
  membership_type VARCHAR(50) DEFAULT 'member',
  
  -- Status and timestamps
  joined_at DATETIME NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  
  -- Indexes
  UNIQUE INDEX index_user_network_memberships_unique (user_id, network_id),
  INDEX index_user_network_memberships_on_network_id (network_id),
  INDEX index_user_network_memberships_on_invitation_id (joined_via_invitation_id),
  INDEX index_user_network_memberships_on_membership_type (membership_type),
  
  -- Foreign keys
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (network_id) REFERENCES networks(id),
  FOREIGN KEY (joined_via_invitation_id) REFERENCES invitations(id)
);
```

### Enhanced Existing Tables

#### invitations
Add network context to invitation codes.

```sql
-- Add network association to invitations
ALTER TABLE invitations 
ADD COLUMN network_id BIGINT REFERENCES networks(id),
ADD COLUMN cross_network_bridge BOOLEAN DEFAULT false,
ADD INDEX index_invitations_on_network_id (network_id);
```

#### trustlines
Add network tracking to credit relationships.

```sql
-- Add network context to trustlines
ALTER TABLE trustlines 
ADD COLUMN primary_network_id BIGINT REFERENCES networks(id),
ADD COLUMN is_cross_network BOOLEAN DEFAULT false,
ADD INDEX index_trustlines_on_primary_network_id (primary_network_id),
ADD INDEX index_trustlines_on_is_cross_network (is_cross_network);
```

### Membership Types

| Type | Description |
|------|-------------|
| `seed` | Original founder of the network |
| `member` | Regular network participant |
| `bridge` | User connected to multiple networks |
| `inactive` | Former member (for historical tracking) |

### Network Types

| Type | Description |
|------|-------------|
| `geographic` | Location-based community (Seattle, Portland, etc.) |
| `sectoral` | Industry-based (Organic Farmers, Restaurants, etc.) |
| `experimental` | Testing network for new features |
| `private` | Invitation-only closed community |

## Core Models

### Network Model

```ruby
# app/models/network.rb
class Network < ApplicationRecord
  belongs_to :seed_user, class_name: 'User'
  has_many :user_network_memberships, dependent: :destroy
  has_many :users, through: :user_network_memberships
  has_many :invitations, dependent: :nullify
  has_many :trustlines, foreign_key: 'primary_network_id'
  
  validates :name, presence: true, uniqueness: true
  validates :network_type, inclusion: { 
    in: %w[geographic sectoral experimental private] 
  }
  validates :max_chain_limit, presence: true, numericality: { 
    greater_than: 0, less_than_or_equal_to: 10 
  }
  
  scope :active, -> { where(is_active: true) }
  scope :launched, -> { where.not(launched_at: nil) }
  scope :by_type, ->(type) { where(network_type: type) }
  
  # Create a new network with seed user
  def self.create_for_seed_user(user, name:, description: nil, network_type: 'geographic')
    transaction do
      network = create!(
        name: name,
        description: description,
        network_type: network_type,
        seed_user: user,
        launched_at: Time.current
      )
      
      # Create seed user membership
      network.user_network_memberships.create!(
        user: user,
        membership_type: 'seed',
        joined_at: Time.current
      )
      
      network
    end
  end
  
  # Network statistics
  def member_count
    user_network_memberships.where(is_active: true).count
  end
  
  def trustline_count
    trustlines.where(is_active: true).count
  end
  
  def bridge_user_count
    users.joins(:user_network_memberships)
         .group('users.id')
         .having('COUNT(user_network_memberships.id) > 1')
         .count
         .size
  end
  
  def total_transaction_volume
    trustlines.joins(:trustline_transactions)
             .sum('trustline_transactions.amount')
  end
  
  # Check if cross-network payments are allowed
  def allows_cross_network_payments?
    allow_cross_network_payments?
  end
  
  # Get network-specific chain limit
  def effective_chain_limit
    max_chain_limit || GlobalSetting.find_by(setting: "ChainLimit")&.value || 5
  end
end
```

### UserNetworkMembership Model

```ruby
# app/models/user_network_membership.rb
class UserNetworkMembership < ApplicationRecord
  belongs_to :user
  belongs_to :network
  belongs_to :joined_via_invitation, class_name: 'Invitation', optional: true
  
  validates :user_id, uniqueness: { scope: :network_id }
  validates :membership_type, inclusion: { 
    in: %w[seed member bridge inactive] 
  }
  
  scope :active, -> { where(is_active: true) }
  scope :by_type, ->(type) { where(membership_type: type) }
  scope :seeds, -> { by_type('seed') }
  scope :bridges, -> { by_type('bridge') }
  
  # Mark user as bridge if they belong to multiple networks
  def check_and_update_bridge_status
    network_count = user.user_network_memberships.active.count
    if network_count > 1 && membership_type != 'bridge'
      update!(membership_type: 'bridge')
    elsif network_count == 1 && membership_type == 'bridge'
      update!(membership_type: 'member')
    end
  end
  
  after_create :check_bridge_status
  after_destroy :check_bridge_status
  
  private
  
  def check_bridge_status
    user.user_network_memberships.each(&:check_and_update_bridge_status)
  end
end
```

### Enhanced User Model

```ruby
# Add to app/models/user.rb
class User < ApplicationRecord
  has_many :user_network_memberships, dependent: :destroy
  has_many :networks, through: :user_network_memberships
  has_many :seeded_networks, class_name: 'Network', foreign_key: 'seed_user_id'
  
  # Network-related methods
  def primary_network
    user_network_memberships.active.first&.network
  end
  
  def network_ids
    user_network_memberships.active.pluck(:network_id)
  end
  
  def is_bridge_user?
    networks.count > 1
  end
  
  def is_seed_user?
    user_network_memberships.seeds.exists?
  end
  
  def can_create_network?
    is_admin? || seeded_networks.empty?
  end
  
  # Network-aware trustline methods
  def trustlines_in_network(network)
    trustlines.where(primary_network_id: network.id)
  end
  
  def cross_network_trustlines
    trustlines.where(is_cross_network: true)
  end
  
  # Enhanced path finding with network scope
  def can_pay_in_network?(amount, to_user, network)
    return false unless networks.include?(network)
    return false unless to_user.networks.include?(network)
    
    # Try direct payment first
    trustline = trustline_with(to_user)
    return true if trustline&.can_handle_payment?(amount, self)
    
    # Try network path finding
    path = Trustline.find_payment_path_in_network(
      self, to_user, amount, network
    )
    !path.nil?
  end
end
```

### Enhanced Trustline Model

```ruby
# Add to app/models/trustline.rb
class Trustline < ApplicationRecord
  belongs_to :primary_network, class_name: 'Network', optional: true
  
  scope :in_network, ->(network) { where(primary_network_id: network.id) }
  scope :cross_network, -> { where(is_cross_network: true) }
  
  # Enhanced path finding with network constraints
  def self.find_payment_path_in_network(from_user, to_user, amount, network, max_hops: nil)
    max_hops ||= network.effective_chain_limit
    
    queue = [[from_user]]
    visited = Set.new([from_user.id])
    
    while queue.any? && queue.first.length <= max_hops
      current_path = queue.shift
      current_user = current_path.last
      
      # Find trustlines within the network
      trustlines = active.in_network(network).for_user(current_user)
      
      trustlines.each do |trustline|
        next_user = trustline.other_user(current_user)
        next unless trustline.can_handle_payment?(amount, current_user)
        next if visited.include?(next_user.id)
        next unless next_user.networks.include?(network)
        
        new_path = current_path + [next_user]
        return new_path if next_user == to_user
        
        queue << new_path
        visited << next_user.id
      end
    end
    
    nil
  end
  
  # Cross-network path finding (when enabled)
  def self.find_cross_network_path(from_user, to_user, amount, max_hops: 2)
    # Implementation for bridge user routing
    # More complex algorithm considering network boundaries
  end
  
  # Determine network for new trustline
  def assign_network
    user_a = User.find(user_a_id)
    user_b = User.find(user_b_id)
    
    common_networks = user_a.networks & user_b.networks
    
    if common_networks.any?
      # Same network relationship
      self.primary_network = common_networks.first
      self.is_cross_network = false
    else
      # Cross-network relationship
      self.primary_network = user_a.primary_network
      self.is_cross_network = true
    end
  end
  
  before_create :assign_network
end
```

### Enhanced Invitation Model

```ruby
# Add to app/models/invitation.rb
class Invitation < ApplicationRecord
  belongs_to :network, optional: true
  
  # Create network membership when invitation is accepted
  def create_network_membership_on_acceptance
    return unless network_id && accepted_user
    
    membership_type = cross_network_bridge? ? 'bridge' : 'member'
    
    UserNetworkMembership.find_or_create_by(
      user: accepted_user,
      network: network
    ) do |membership|
      membership.joined_via_invitation = self
      membership.membership_type = membership_type
      membership.joined_at = Time.current
    end
  end
  
  # Override to include network context
  def generate_invitation_code
    super
    
    # Auto-assign to user's primary network if not specified
    if network_id.nil? && user.primary_network
      self.network_id = user.primary_network.id
    end
  end
  
  def network_name
    network&.name || "Global Network"
  end
  
  after_update :create_network_membership_on_acceptance, if: :saved_change_to_status?
end
```

## API Enhancements

### Network Management Endpoints

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :networks, only: [:index, :show, :create, :update] do
      member do
        get :members
        get :analytics
        get :trustlines
        post :join
        delete :leave
      end
    end
  end
end
```

### Networks Controller

```ruby
# app/controllers/api/v1/networks_controller.rb
class Api::V1::NetworksController < Api::V1::ApiController
  before_action :set_network, only: [:show, :update, :members, :analytics, :trustlines, :join, :leave]
  
  # GET /api/v1/networks
  def index
    @networks = Network.active.includes(:seed_user)
    
    # Filter by user's networks if requested
    if params[:user_networks] == 'true'
      @networks = @networks.joins(:user_network_memberships)
                          .where(user_network_memberships: { user_id: current_user.id, is_active: true })
    end
    
    render json: @networks.map { |network| network_summary(network) }
  end
  
  # GET /api/v1/networks/:id
  def show
    render json: network_details(@network)
  end
  
  # POST /api/v1/networks
  def create
    unless current_user.can_create_network?
      render json: { errors: ['Not authorized to create networks'] }, status: 403
      return
    end
    
    @network = Network.create_for_seed_user(
      current_user,
      name: params[:name],
      description: params[:description],
      network_type: params[:network_type] || 'geographic'
    )
    
    if @network.persisted?
      render json: network_details(@network), status: 201
    else
      render json: { errors: @network.errors.full_messages }, status: 422
    end
  end
  
  # GET /api/v1/networks/:id/members
  def members
    memberships = @network.user_network_memberships.active.includes(:user)
    
    render json: memberships.map do |membership|
      {
        user: {
          id: membership.user.id,
          name: membership.user.user_name
        },
        membership_type: membership.membership_type,
        joined_at: membership.joined_at
      }
    end
  end
  
  # GET /api/v1/networks/:id/analytics
  def analytics
    render json: {
      member_count: @network.member_count,
      trustline_count: @network.trustline_count,
      bridge_user_count: @network.bridge_user_count,
      total_transaction_volume: @network.total_transaction_volume,
      growth_metrics: calculate_growth_metrics(@network)
    }
  end
  
  private
  
  def set_network
    @network = Network.find(params[:id])
  end
  
  def network_summary(network)
    {
      id: network.id,
      name: network.name,
      network_type: network.network_type,
      member_count: network.member_count,
      seed_user: network.seed_user.user_name,
      launched_at: network.launched_at
    }
  end
  
  def network_details(network)
    network_summary(network).merge(
      description: network.description,
      settings: {
        max_chain_limit: network.max_chain_limit,
        allow_cross_network_payments: network.allow_cross_network_payments?,
        default_invitation_limit: network.default_invitation_limit
      },
      analytics: {
        trustline_count: network.trustline_count,
        bridge_user_count: network.bridge_user_count
      }
    )
  end
  
  def calculate_growth_metrics(network)
    # Implementation for growth analytics
    {}
  end
end
```

### Enhanced Trustline API

```ruby
# Add to app/controllers/api/v1/trustlines_controller.rb

# Network-aware path finding
def find_path
  network_scope = params[:network_scope] || 'current_network'
  
  case network_scope
  when 'current_network'
    network = current_user.primary_network
    path = Trustline.find_payment_path_in_network(
      current_user, 
      User.find(params[:to_user_id]), 
      params[:amount].to_f,
      network,
      max_hops: params[:max_hops]&.to_i
    )
  when 'all_networks'
    path = Trustline.find_payment_path(
      current_user,
      User.find(params[:to_user_id]),
      params[:amount].to_f,
      max_hops: params[:max_hops]&.to_i
    )
  end
  
  if path
    render json: {
      path_found: true,
      path: path.map { |user| { id: user.id, name: user.user_name } },
      path_length: path.length - 1,
      network_scope: network_scope
    }
  else
    render json: {
      path_found: false,
      message: "No payment path found within specified constraints"
    }
  end
end

# Network-aware summary
def summary
  network_id = params[:network_id]
  
  if network_id
    network = Network.find(network_id)
    trustlines = current_user.trustlines_in_network(network)
  else
    trustlines = current_user.trustlines
  end
  
  # Calculate summary for specified network or all networks
  render json: calculate_financial_summary(trustlines)
end
```

### Enhanced Invitations API

```ruby
# Add to app/controllers/api/v1/invitations_controller.rb

def create
  @invitation = current_user.invitations.build(invitation_params)
  
  # Auto-assign network if not specified
  if invitation_params[:network_id].blank?
    @invitation.network = current_user.primary_network
  end
  
  if @invitation.save
    render json: invitation_response(@invitation), status: 201
  else
    render json: { errors: @invitation.errors.full_messages }, status: 422
  end
end

private

def invitation_params
  params.permit(:user_type, :network_id, :cross_network_bridge, :label, :note_label)
end

def invitation_response(invitation)
  {
    invitation_code: invitation.invitation_code,
    user_type: invitation.user_type,
    network: {
      id: invitation.network&.id,
      name: invitation.network&.name
    },
    cross_network_bridge: invitation.cross_network_bridge?
  }
end
```

## Rollout Strategy

### Phase 1: Network Foundation (Week 1-2)

**Goal**: Deploy seed users in target areas with network creation capability

**Activities**:
1. **Database Migration**: Add networks tables and enhance existing tables
2. **Seed User Deployment**: 
   ```ruby
   # Seattle seed user
   seattle_user = User.create!(user_name: "seattle_seed", password: "secure_password")
   seattle_user.user_groups.create!(group_label: "admin")
   seattle_network = Network.create_for_seed_user(
     seattle_user,
     name: "Seattle Food Network",
     description: "Local food distribution for Seattle metro area"
   )
   
   # Portland seed user  
   portland_user = User.create!(user_name: "portland_seed", password: "secure_password")
   portland_user.user_groups.create!(group_label: "admin")
   portland_network = Network.create_for_seed_user(
     portland_user,
     name: "Portland Producers",
     description: "Oregon producer and retailer network"
   )
   ```

3. **Initial Testing**: Seed users test invitation generation and basic network functionality

### Phase 2: Network Growth (Week 3-8)

**Goal**: Each network grows to 10-20 active members through invitation chains

**Activities**:
1. **Seed User Invitations**: Each seed user invites 3-5 key community members
2. **Second-Generation Growth**: Initial invitees invite their contacts
3. **Network Health Monitoring**: Track growth metrics and transaction patterns
4. **Community Building**: Seed users facilitate introductions and initial trades

**Expected Growth Pattern**:

Week 3: 3-5 members per network (seed + initial invites)
Week 4: 6-10 members (second generation joins)
Week 6: 10-15 members (network effects begin)
Week 8: 15-25 members (sustainable community size)



### Phase 3: Network Maturation (Week 9-12)

**Goal**: Networks become self-sustaining with regular transaction activity

**Activities**:
1. **Transaction Volume Growth**: Members begin regular trading
2. **Trustline Network Development**: Users establish multiple credit relationships
3. **Role Diversification**: Producer, broker, retailer, consumer roles emerge
4. **Network Governance**: Community guidelines and practices develop

### Phase 4: Cross-Network Connections (Week 13+)

**Goal**: Bridge users emerge connecting different networks

**Activities**:
1. **Bridge User Identification**: Users with connections in multiple areas
2. **Cross-Network Trustlines**: Enable payments between networks
3. **Network Interconnection**: Gradual integration of separate communities
4. **Performance Optimization**: Enhance path-finding for cross-network payments

## Implementation Phases

### Phase 1: Database & Core Models (Sprint 1)

**Database Changes**:
- [ ] Create `networks` table
- [ ] Create `user_network_memberships` table  
- [ ] Add `network_id` to `invitations` table
- [ ] Add `primary_network_id` and `is_cross_network` to `trustlines` table
- [ ] Create database indexes for performance

**Model Enhancements**:
- [ ] Implement `Network` model with validations and methods
- [ ] Implement `UserNetworkMembership` model
- [ ] Enhance `User` model with network-aware methods
- [ ] Enhance `Trustline` model with network path-finding
- [ ] Enhance `Invitation` model with network assignment

### Phase 2: API Development (Sprint 2)

**New API Endpoints**:
- [ ] Networks CRUD endpoints (`/api/v1/networks`)
- [ ] Network membership management
- [ ] Network analytics endpoints

**Enhanced Existing APIs**:
- [ ] Add network context to trustline path-finding
- [ ] Add network filtering to financial summaries
- [ ] Add network assignment to invitation generation
- [ ] Add network-aware user queries

### Phase 3: Frontend Integration (Sprint 3)

**UI Components**:
- [ ] Network selection in invitation generation
- [ ] Network membership display in user profiles
- [ ] Network analytics dashboard for seed users
- [ ] Network-aware contact filtering

**Enhanced Existing UI**:
- [ ] Add network context to trustline management
- [ ] Add network filtering to transaction history
- [ ] Add network scope to payment path finding

### Phase 4: Testing & Documentation (Sprint 4)

**Testing**:
- [ ] Unit tests for all new models and methods
- [ ] Integration tests for network-aware APIs
- [ ] End-to-end tests for multi-network scenarios
- [ ] Performance tests for network path-finding

**Documentation**:
- [ ] API documentation updates
- [ ] User guide for network features
- [ ] Admin guide for network management
- [ ] Database schema documentation

## Benefits & Considerations

### Benefits

**For System Architecture**:
- **Performance**: Smaller network graphs improve path-finding speed
- **Scalability**: System can handle many independent communities
- **Flexibility**: Different networks can have different rules/limits
- **Analytics**: Network-specific metrics and health monitoring

**For Business Strategy**:
- **Organic Growth**: Natural community formation through invitation chains
- **Market Testing**: Test different approaches in different networks
- **Risk Mitigation**: Issues contained within individual networks
- **Community Building**: Stronger local connections and engagement

**For Users**:
- **Relevant Connections**: See contacts and opportunities in their area
- **Community Identity**: Belong to a named, local network
- **Bridge Opportunities**: Connect multiple communities for broader reach
- **Performance**: Faster payment processing within local networks

### Considerations & Trade-offs

**Technical Complexity**:
- **Database Complexity**: Additional tables and relationships
- **API Complexity**: Network context in all relevant endpoints
- **Path-Finding Complexity**: Network-aware algorithms more complex
- **Data Migration**: Careful handling of existing data

**Business Considerations**:
- **Network Effects**: Smaller networks have fewer payment paths
- **User Experience**: Additional complexity in UI and workflows
- **Governance**: Network management and administration overhead
- **Cross-Network Integration**: Complexity of bridge users and cross-network payments

**Mitigation Strategies**:
- **Gradual Rollout**: Implement incrementally with thorough testing
- **Default Behavior**: Make network-aware features optional initially
- **Performance Monitoring**: Track impact on system performance
- **User Education**: Clear documentation and onboarding for network concepts

## Migration Guide

### For New Installations

1. **Run Migrations**: Standard Rails migration process
2. **Create Default Network**: For any existing users
3. **Assign Trustlines**: Associate existing trustlines with default network
4. **Configure Settings**: Set default network limits and permissions

### For Existing Systems

```ruby
# Migration: 20240301000001_add_networks_support.rb
class AddNetworksSupport < ActiveRecord::Migration[7.0]
  def up
    # Create new tables
    create_networks_table
    create_user_network_memberships_table
    
    # Enhance existing tables
    add_network_columns_to_invitations
    add_network_columns_to_trustlines
    
    # Create default network for existing users
    create_default_network_if_needed
  end
  
  def down
    # Careful rollback process
    remove_network_columns_from_trustlines
    remove_network_columns_from_invitations
    drop_table :user_network_memberships
    drop_table :networks
  end
  
  private
  
  def create_default_network_if_needed
    return unless User.exists?
    
    admin_user = User.joins(:user_groups)
                    .where(user_groups: { group_label: 'admin' })
                    .first
    
    if admin_user
      default_network = Network.create!(
        name: "Founding Network",
        description: "Original community network",
        network_type: "geographic",
        seed_user: admin_user,
        launched_at: Time.current
      )
      
      # Add all existing users to default network
      User.find_each do |user|
        UserNetworkMembership.create!(
          user: user,
          network: default_network,
          membership_type: user == admin_user ? 'seed' : 'member',
          joined_at: user.created_at
        )
      end
      
      # Associate existing trustlines with default network
      Trustline.update_all(primary_network_id: default_network.id)
    end
  end
end
```

### Testing Network Features

```ruby
# spec/models/network_spec.rb
RSpec.describe Network, type: :model do
  describe '.create_for_seed_user' do
    let(:user) { create(:user) }
    
    it 'creates network and seed membership' do
      network = Network.create_for_seed_user(
        user,
        name: "Test Network",
        description: "Test description"
      )
      
      expect(network.persisted?).to be true
      expect(network.seed_user).to eq user
      expect(network.users).to include user
      expect(network.user_network_memberships.seeds.count).to eq 1
    end
  end
  
  describe '#member_count' do
    it 'returns active member count' do
      network = create(:network)
      create_list(:user_network_membership, 3, network: network)
      create(:user_network_membership, network: network, is_active: false)
      
      expect(network.member_count).to eq 4 # 3 active + 1 seed
    end
  end
end

# spec/models/user_spec.rb
RSpec.describe User, type: :model do
  describe '#is_bridge_user?' do
    let(:user) { create(:user) }
    
    it 'returns true when user belongs to multiple networks' do
      network1 = create(:network)
      network2 = create(:network)
      
      create(:user_network_membership, user: user, network: network1)
      create(:user_network_membership, user: user, network: network2)
      
      expect(user.is_bridge_user?).to be true
    end
  end
end
```

---

## Summary

The networks architecture provides a robust foundation for multi-community mutual credit systems that:

1. **Supports Organic Growth**: Seed users create networks that grow through invitation chains
2. **Maintains Performance**: Network-scoped operations prevent system slowdown
3. **Enables Flexibility**: Different networks can have different rules and governance
4. **Allows Integration**: Bridge users naturally connect mature networks
5. **Provides Analytics**: Network-specific metrics for health monitoring

This architecture aligns perfectly with the planned rollout strategy while maintaining the flexibility to evolve as the system grows and communities interconnect.

The implementation can be done incrementally, starting with core database changes and models, then adding API support, and finally enhancing the user interface. Each phase can be thoroughly tested before moving to the next, ensuring system stability throughout the rollout process.