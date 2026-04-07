# Mutual Credit System Documentation

## Overview

This Rails backend implements a **mutual credit system** that enables users to extend credit to each other and facilitate payments through a network of trust relationships. It's designed to support a local food distribution platform where producers, retailers, and consumers can trade goods using community credit instead of traditional money.

The system creates a **network economy** where users establish bidirectional credit relationships (trustlines) and can make payments either directly to connected users or through multi-hop routing across the network.

## Table of Contents

- [Core Architecture](#core-architecture)
- [Key Concepts](#key-concepts)
- [Database Schema](./database_schema.md)
- [API Reference](./api_reference.md)
- [Payment Flows](./payment_flows.md)
- [Integration Guide](./integration.md)
- [Examples](./examples.md)

## Core Architecture

### Key Components

1. **Trustlines** - Bidirectional credit relationships between users
2. **Trustline Transactions** - Complete audit trail of all credit movements
3. **Payment Routing** - Multi-hop payment paths through the network
4. **Item Integration** - Seamless integration with item requests and orders

### Core Models

- **`Trustline`** - Core relationship between two users with bidirectional credit limits
- **`TrustlineTransaction`** - Every payment/adjustment with full audit trail
- **`User`** - Extended with mutual credit methods for network position calculation

## Key Concepts

### Credit Relationships

Each trustline represents a bidirectional credit relationship:
- **User A → User B**: Credit limit A extends to B
- **User B → User A**: Credit limit B extends to A
- **Current Balance**: Net position between users
- **Available Credit**: How much each user can still spend

### Balance Calculations

```
Positive balance = user_a owes user_b
Negative balance = user_b owes user_a
Available credit = credit_limit - max(current_balance, 0)
```

### Payment Types

1. **Direct Payments** - Between users with direct trustlines
2. **Multi-hop Payments** - Routed through intermediate users
3. **Settlements** - External settlements outside the app
4. **Adjustments** - Administrative balance corrections
5. **Reversals** - Cancellation of previous transactions

## Core Functionality

### 1. Trustline Management

- **Bidirectional credit limits**: Each user sets how much credit they extend to the other
- **Balance tracking**: Real-time net position between users
- **User ordering constraint**: Prevents duplicate relationships (user_a_id < user_b_id)
- **Soft delete**: Trustlines deactivated rather than deleted to preserve history

### 2. Payment Processing

**Direct Payments**:
- Users can pay anyone they have an active trustline with
- Available credit = credit limit - current outstanding balance
- Atomic balance updates with full transaction recording

**Multi-hop Payments**:
- **Path finding**: Breadth-first search to find shortest viable route
- **Network routing**: Payment automatically routed through intermediate users
- **Atomic execution**: All hops succeed or all fail (database transactions)
- **Configurable limits**: Maximum 5 hops by default

### 3. Financial Analytics

Users can track:
- Total credit owed to others
- Total credit others owe to user  
- Net credit position (creditor vs debtor)
- Available credit across all trustlines
- Recent transaction history

### 4. Credloop Clearing

**Automatic Cycle Detection**:
- System automatically detects credit cycles (loops) in the debt network
- Uses recursive depth-first search to find circular debt paths
- Handles loops of any length (2 users, 3 users, 10+ users)
- Runs after every debt creation or modification

**Automatic Clearing**:
- All debts in a cycle are reduced by the minimum amount in the loop
- Clearing happens atomically in a database transaction
- Fully cleared debts are automatically removed
- Example: Alice owes Bob $10, Bob owes Carol $8, Carol owes Alice $6 → all reduced by $6

**Complete Audit Trail**:
- Every clearing event is recorded with timestamp and participants count
- Each individual debt adjustment is tracked with before/after amounts
- Users see their perspective of each clearing in transaction history
- Full transparency showing why balances changed and which loop was closed

## Integration with Item System

The mutual credit system is deeply integrated with the existing food distribution platform:

1. **Item Requests**: When users accept item requests, payments can be automatically processed through trustlines
2. **Order Management**: Orders link to trustline transactions for payment tracking
3. **Supply Chain**: Multi-step supply chains (producer → retailer → consumer) create corresponding payment chains
4. **Audit Trail**: Every item exchange has corresponding trustline transaction record

## Technical Implementation

### User Model Extensions

```ruby
# Financial position calculations
user.total_credit_owed          # What I owe others
user.total_credit_owed_to_me    # What others owe me  
user.net_credit_position        # Net position in network
user.available_credit_total     # Total spendable credit

# Relationship management
user.trustlines                 # All trustlines
user.active_trustlines         # Active only
user.trustline_with(other_user) # Specific relationship
user.establish_trustline_with(other_user, limits) # Create/find trustline
```

### Payment Path Algorithm

- **Breadth-first search** for shortest viable path
- **Credit validation** at each hop before adding to queue
- **Cycle prevention** using visited user tracking
- **Configurable constraints** (max hops, minimum amounts)

### Transaction Safety

- **Database transactions** ensure atomic multi-hop payments
- **Balance validation** before processing any payment
- **Audit trail preservation** with transaction reversal rather than deletion
- **Concurrent access protection** through row-level locking

## Business Logic & Constraints

### Credit Limits
- Each direction has independent credit limit
- Users can't spend beyond their available credit
- Available credit = limit - current balance owed

### Balance Calculations
- Positive balance: user_a owes user_b
- Negative balance: user_b owes user_a
- Each user sees their perspective (positive = they owe, negative = owed to them)

### Transaction Types
- **Payment**: Regular user-to-user payment
- **Settlement**: External settlement (outside app)
- **Adjustment**: Administrative balance correction  
- **Reversal**: Cancellation of previous transaction

## Current Status

The system is implemented on the `feature/mutual-credit-system` branch and appears to be **production-ready** with:
- Complete database schema with proper indexes
- Full CRUD API with authentication/authorization  
- Comprehensive test coverage
- Integration with existing item request workflow
- Advanced features like multi-hop routing

The code is well-documented with extensive inline comments explaining the mutual credit concepts and implementation details.

This system enables a **community-driven economy** where trust relationships replace traditional banking, making it ideal for local food networks, community-supported agriculture, and alternative economic models.

## Quick Start

1. [Set up trustlines](./examples.md#creating-trustlines) between users
2. [Make direct payments](./examples.md#direct-payments) through trustlines
3. [Execute multi-hop payments](./examples.md#multi-hop-payments) across the network
4. [Integrate with item requests](./integration.md#item-request-integration) for automatic payments

## Further Reading

- [API Reference](./api_reference.md) - Complete API documentation
- [Database Schema](./database_schema.md) - Detailed database structure
- [Payment Flows](./payment_flows.md) - Step-by-step payment processes
- [Integration Guide](./integration.md) - How to integrate with existing systems
- [Examples](./examples.md) - Code examples and use cases 