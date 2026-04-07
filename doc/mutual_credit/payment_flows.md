# Payment Flows Documentation

This document describes the different payment flows supported by the mutual credit system.

## Overview

The mutual credit system supports several types of payment flows:

1. **Direct Payments** - Between users with direct trustlines
2. **Multi-hop Payments** - Routed through intermediate users  
3. **Item Request Payments** - Triggered by accepting item requests
4. **Settlement Payments** - External settlements outside the app
5. **Adjustment Payments** - Administrative balance corrections

## 1. Direct Payment Flow

The simplest payment flow between two users who have an established trustline.

### Prerequisites

- Both users have an active trustline
- Paying user has sufficient available credit
- Trustline is active and not deactivated

### Flow Diagram

```
[User A] -------- [Trustline] -------- [User B]
   |                   |                   |
   |------ Payment ---->                   |
                       |                   |
                  Update Balance      Receive Credit
```

### API Sequence

1. **Check Available Credit**
   ```http
   GET /api/v1/trustlines/summary
   ```

2. **Process Payment**
   ```http
   POST /api/v1/trustlines/:id/payment
   {
     "amount": "150.00",
     "description": "Payment for vegetables"
   }
   ```

3. **Verify New Balance**
   ```http
   GET /api/v1/trustlines/:id
   ```

### Database Operations

```ruby
# 1. Validate payment
trustline.can_handle_payment?(amount, current_user)

# 2. Process atomically
ActiveRecord::Base.transaction do
  # Update balance
  new_balance = trustline.current_balance + amount
  
  # Create transaction record
  trustline.trustline_transactions.create!(
    amount: amount,
    description: description,
    transaction_type: 'payment',
    initiated_by: current_user,
    balance_after: new_balance
  )
  
  # Update trustline
  trustline.update!(
    current_balance: new_balance,
    last_activity: Time.current
  )
end
```

## 2. Multi-hop Payment Flow

Payment routed through multiple intermediate users when no direct trustline exists.

### Prerequisites

- Path exists between sender and receiver
- Each hop has sufficient credit
- Maximum hop limit not exceeded (default: 5)

### Flow Diagram

```
[User A] -- [Trustline 1] -- [User B] -- [Trustline 2] -- [User C]
    |                           |                           |
    |--------- Multi-hop Payment (via B) ------------------>|
                                 |
                        Intermediate User
                       (Routing Node)
```

### Path Finding Algorithm

1. **Breadth-first search** from sender
2. **Credit validation** at each hop
3. **Cycle prevention** using visited tracking
4. **Shortest path selection**

```ruby
def self.find_payment_path(from_user, to_user, amount, max_hops: 5)
  queue = [[from_user]]
  visited = Set.new([from_user.id])
  
  while queue.any? && queue.first.length <= max_hops
    current_path = queue.shift
    current_user = current_path.last
    
    # Find all active trustlines for current user
    trustlines = Trustline.active.for_user(current_user)
    
    trustlines.each do |trustline|
      next_user = trustline.other_user(current_user)
      next unless trustline.can_handle_payment?(amount, current_user)
      next if visited.include?(next_user.id)
      
      new_path = current_path + [next_user]
      return new_path if next_user == to_user
      
      queue << new_path
      visited << next_user.id
    end
  end
  
  nil # No viable path found
end
```

### API Sequence

1. **Find Payment Path**
   ```http
   POST /api/v1/trustlines/find_path
   {
     "to_user_id": 5,
     "amount": "200.00",
     "max_hops": 3
   }
   ```

2. **Execute Path Payment**
   ```http
   POST /api/v1/trustlines/execute_path_payment
   {
     "to_user_id": 5,
     "amount": "200.00",
     "description": "Multi-hop payment",
     "max_hops": 3
   }
   ```

### Transaction Processing

```ruby
# Process each hop atomically
ActiveRecord::Base.transaction do
  path.each_cons(2) do |from_user, to_user|
    trustline = Trustline.between_users(from_user, to_user).first
    
    trustline.process_payment!(
      amount, 
      from_user, 
      to_user, 
      description: description
    )
  end
end
```

## 3. Item Request Payment Flow

Payments automatically triggered when users accept item requests.

### Prerequisites

- Item request exists and is pending
- Users have trustline or viable payment path
- Sufficient credit available

### Flow Diagram

```
[Consumer] ---- Item Request ----> [Producer]
     |                                |
     |                           Accept Request
     |                                |
     |<---- Automatic Payment --------|
                     |
              Trustline Network
```

### Integration Points

1. **Item Request Model**
   ```ruby
   # app/models/item_request.rb
   belongs_to :originating_request, class_name: 'ItemRequest', optional: true
   ```

2. **Trustline Transaction Model**
   ```ruby
   # app/models/trustline_transaction.rb
   belongs_to :originating_request, class_name: 'ItemRequest', optional: true
   ```

### API Sequence

1. **Accept Item Request**
   ```http
   POST /api/v1/items/requests/:id/accept
   ```

2. **Automatic Payment Processing**
   ```ruby
   # In ItemRequestsController#accept
   if item_request.update(status: :accepted)
     # Trigger automatic payment
     process_trustline_payment(item_request)
   end
   ```

3. **Payment with Request Link**
   ```http
   POST /api/v1/trustlines/:id/payment
   {
     "amount": "150.00",
     "description": "Payment for item request #42",
     "originating_request_id": 42
   }
   ```

## 4. Settlement Payment Flow

External settlements for balances resolved outside the application.

### Use Cases

- Cash payments between users
- Bank transfers
- Physical goods exchange
- Debt forgiveness

### Flow Diagram

```
[User A] ---- [Trustline] ---- [User B]
    |             |                |
    |        External Settlement   |
    |             |                |
    |------ Settlement Record ---->|
                  |
           Update Balance
```

### API Sequence

```http
POST /api/v1/trustlines/:id/settlement
{
  "amount": "500.00",
  "description": "Cash payment settlement",
  "settlement_type": "cash"
}
```

### Database Operations

```ruby
# Create settlement transaction
trustline.trustline_transactions.create!(
  amount: amount,
  description: description,
  transaction_type: 'settlement',
  initiated_by: current_user,
  balance_after: new_balance
)
```

## 5. Adjustment Payment Flow

Administrative balance corrections and system adjustments.

### Use Cases

- Correcting data entry errors
- System migration adjustments
- Dispute resolutions
- Administrative corrections

### Flow Diagram

```
[Admin User] ---- [System] ---- [Trustline]
      |              |               |
      |         Adjustment           |
      |              |               |
      |------ Admin Action --------->|
                     |
            Update Balance + Audit
```

### Authorization

- Only admin users can make adjustments
- Full audit trail maintained
- Reason required for all adjustments

### API Sequence

```http
POST /api/v1/admin/trustlines/:id/adjustment
{
  "amount": "25.00",
  "adjustment_type": "correction",
  "reason": "Correcting data entry error from 2024-06-15"
}
```

## 6. Transaction Reversal Flow

Cancelling or reversing previous transactions while maintaining audit trail.

### Principles

- Never delete transaction records
- Create counteracting reversal transactions
- Maintain complete audit trail
- Balance integrity preserved

### Flow Diagram

```
[Original Transaction] ---- [Reversal Request] ---- [Reversal Transaction]
          |                        |                        |
     Amount: +150              Reason Given            Amount: -150
          |                        |                        |
     Balance: 300              Admin Review             Balance: 150
```

### API Sequence

```http
POST /api/v1/trustlines/transactions/:id/reverse
{
  "reason": "Duplicate payment - customer error"
}
```

### Database Operations

```ruby
# Create reversal transaction
reversal = original_transaction.trustline.trustline_transactions.create!(
  amount: original_transaction.amount,
  description: "Reversal: #{reason}",
  transaction_type: 'reversal',
  initiated_by: current_user,
  balance_after: adjusted_balance
)

# Mark original as reversed
original_transaction.update!(is_reversed: true)

# Update trustline balance
trustline.update!(current_balance: adjusted_balance)
```

## 7. Credloop Clearing Flow

Automatic detection and clearing of credit cycles in the debt network.

### Prerequisites

- Credit cycles exist in the network
- System enabled for automatic clearing
- Sufficient audit trail capacity

### What is a Credloop?

A **credloop** (credit loop/cycle) occurs when users owe each other in a circular pattern:

```
Alice owes Bob $10
Bob owes Carol $8  
Carol owes Alice $6

→ This forms a cycle: Alice → Bob → Carol → Alice
```

The system automatically detects these cycles and clears them by reducing all debts by the minimum amount in the loop.

### Flow Diagram

```
[User A] --$10--> [User B] --$8--> [User C]
    ↑                                  |
    |                                  |
    +---------------$6-----------------+
                  (Credit Loop)
                       |
                  Auto-Detect
                       |
                  Clear Loop
                       |
                  Result:
    [User A] --$4--> [User B] --$2--> [User C]
           (All debts reduced by $6)
```

### Automatic Trigger

Credloop clearing runs automatically after any debt creation or modification:

```ruby
# app/models/debt.rb
class Debt < ApplicationRecord
  after_commit :clear_credloops, on: [:create, :update]
  
  private
  
  def clear_credloops
    CredLoopService.find_and_clear_all_loops_involving(debtor, creditor)
  end
end
```

No API calls needed - the system handles clearing transparently.

### Detection Algorithm

Uses recursive depth-first search to find cycles of any length:

```ruby
def find_credloop(start_user, current_user, path, visited_in_path)
  # Base case: we've circled back to the start
  if current_user == start_user && path.length > 1
    return path
  end
  
  # Recursive case: explore all debts this user owes
  current_user.debts_as_debtor.each do |debt|
    next_user = debt.creditor
    
    # Skip if already visited (prevents infinite loops)
    next if visited_in_path.include?(next_user.id)
    
    # Recurse down this path
    result = find_credloop(
      start_user,
      next_user,
      path + [debt],
      visited_in_path + Set[next_user.id]
    )
    
    return result if result.present?
  end
  
  nil # No loop found
end
```

### Database Operations

```ruby
# Process credloop clearing
ActiveRecord::Base.transaction do
  # Find minimum amount in loop
  min_amount = debts_in_loop.map(&:amount).min
  
  # Create clearing record
  clearing = CredLoopClearing.create!(
    amount_cleared: min_amount,
    participants_count: debts_in_loop.length
  )
  
  # Reduce each debt atomically
  debts_in_loop.each_with_index do |debt, index|
    before = debt.amount
    debt.amount -= min_amount
    after = debt.amount
    
    # Record adjustment
    CredLoopAdjustment.create!(
      credloop_clearing: clearing,
      debt: debt,
      user: debt.debtor,
      amount_reduced: min_amount,
      before_amount: before,
      after_amount: after,
      position_in_loop: index + 1
    )
    
    # Remove fully cleared debts
    if debt.amount <= 0
      debt.destroy
    else
      debt.save!
    end
  end
end
```

### User Visibility

Each user sees credloop clearings in their transaction history:

```
┌─────────────────────────────────────────────────────┐
│ Credloop Clearing #127                              │
│ January 15, 2025 at 3:42 PM                         │
├─────────────────────────────────────────────────────┤
│                                                      │
│ Your debt to Bob Gardener:                          │
│ $10.00 → $5.00 (-$5.00)                             │
│                                                      │
│ This was cleared because a credit loop was closed:  │
│                                                      │
│  1. Alice Chen owed you $5.00                       │
│  2. You owed Bob Gardener $5.00                     │
│  3. Bob Gardener owed Alice Chen $5.00              │
│                                                      │
│ All three debts were reduced by $5.00               │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Examples

**2-Party Loop (Mutual Debts):**
```ruby
# Before clearing
Alice owes Bob $100
Bob owes Alice $75

# After automatic clearing
Alice owes Bob $25
Bob owes Alice $0 (debt removed)
```

**3-Party Loop:**
```ruby
# Before clearing
Alice owes Bob $50
Bob owes Carol $40
Carol owes Alice $30

# After automatic clearing (min=$30)
Alice owes Bob $20
Bob owes Carol $10
Carol owes Alice $0 (debt removed)
```

**Multi-Loop Scenario:**
```ruby
# User participates in multiple loops simultaneously
# Each loop is detected and cleared independently
# All operations are atomic
```

### Audit Trail

Complete transparency with two-table system:

1. **CredLoopClearing** - Records each clearing event
   - Amount cleared
   - Participants count
   - Timestamp

2. **CredLoopAdjustment** - Records each debt adjustment
   - Before/after amounts
   - User perspective
   - Position in loop

Every user can see:
- Which of their debts was reduced
- Why it was reduced (the complete loop)
- By how much it was reduced
- When it occurred

### Performance

For MVP (< 1000 users):
- **Synchronous execution** - runs immediately after debt creation
- **Fast detection** - milliseconds for typical networks
- **Minimal overhead** - only searches involving transaction users

For scale (1000+ users):
- **Background jobs** - async processing with Sidekiq
- **Caching** - store known loop-free segments
- **Rate limiting** - prevent DoS from rapid transactions
- **Incremental search** - only check new paths

## Error Handling and Edge Cases

### Insufficient Credit

```ruby
# Check before processing
unless trustline.can_handle_payment?(amount, current_user)
  raise InsufficientCreditError, "Available credit: #{available_credit}"
end
```

### Network Partitioning

```ruby
# No path found
if path.nil?
  raise NoPaymentPathError, "No viable path within #{max_hops} hops"
end
```

### Concurrent Transactions

```ruby
# Use database locking
ActiveRecord::Base.transaction do
  trustline.lock! # Row-level lock
  # Process payment
end
```

### Balance Reconciliation

```ruby
# Periodic balance verification
def verify_balance_integrity
  calculated_balance = trustline_transactions
    .where(is_reversed: false)
    .sum(&:signed_amount_for_trustline)
    
  unless current_balance == calculated_balance
    raise BalanceIntegrityError, "Balance mismatch detected"
  end
end
```

## Performance Considerations

### Path Finding Optimization

- **Limit search depth** (max 5 hops)
- **Cache frequent paths** for popular routes
- **Pre-compute** paths for regular trading partners
- **Index optimization** for user relationships

### Transaction Volume

- **Batch processing** for high-volume periods
- **Async processing** for non-critical updates
- **Database sharding** for large user bases
- **Read replicas** for balance queries

### Monitoring and Alerts

```ruby
# Monitor payment success rates
Rails.logger.info "Payment processed: #{amount} from #{from_user.id} to #{to_user.id}"

# Alert on failures
if payment_failure_rate > threshold
  AdminMailer.payment_system_alert.deliver_now
end
```

## Security Considerations

### Payment Authorization

- **JWT authentication** required for all payments
- **User authorization** - can only spend own credit
- **Amount validation** - positive amounts only
- **Rate limiting** on payment endpoints

### Audit Trail

- **Immutable records** - never delete transactions
- **Complete traceability** - link to originating requests
- **Admin oversight** - all adjustments logged
- **Balance verification** - periodic integrity checks

### Data Integrity

- **Atomic transactions** for multi-hop payments
- **Consistent balance** calculations
- **Duplicate prevention** using idempotency keys
- **Rollback capability** for failed operations

This comprehensive payment flow system enables a robust mutual credit economy with full auditability, security, and scalability. 