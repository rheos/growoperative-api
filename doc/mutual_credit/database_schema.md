# Mutual Credit Database Schema

This document describes the database schema for the mutual credit system.

## Overview

The mutual credit system consists of two main tables:
- `trustlines` - Stores bidirectional credit relationships between users
- `trustline_transactions` - Records all credit movements for audit trail

## Tables

### trustlines

Stores bidirectional credit relationships between users.

```sql
CREATE TABLE trustlines (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  -- User relationship (ordered: user_a_id < user_b_id)
  user_a_id BIGINT NOT NULL,
  user_b_id BIGINT NOT NULL,
  
  -- Bidirectional credit limits
  credit_limit_a_to_b DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  credit_limit_b_to_a DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  
  -- Current net balance
  current_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  
  -- Status and metadata
  is_active BOOLEAN NOT NULL DEFAULT true,
  established_date DATETIME NOT NULL,
  last_activity DATETIME,
  notes TEXT,
  
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  
  -- Indexes
  UNIQUE INDEX index_trustlines_on_user_pair (user_a_id, user_b_id),
  INDEX index_trustlines_on_user_a_id (user_a_id),
  INDEX index_trustlines_on_user_b_id (user_b_id),
  INDEX index_trustlines_on_is_active (is_active),
  INDEX index_trustlines_on_established_date (established_date),
  
  -- Foreign keys
  FOREIGN KEY (user_a_id) REFERENCES users(id),
  FOREIGN KEY (user_b_id) REFERENCES users(id)
);
```

#### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `user_a_id` | BIGINT | First user in relationship (always < user_b_id) |
| `user_b_id` | BIGINT | Second user in relationship (always > user_a_id) |
| `credit_limit_a_to_b` | DECIMAL(10,2) | Maximum credit user_a can extend to user_b |
| `credit_limit_b_to_a` | DECIMAL(10,2) | Maximum credit user_b can extend to user_a |
| `current_balance` | DECIMAL(10,2) | Net balance (+ = user_a owes user_b, - = user_b owes user_a) |
| `is_active` | BOOLEAN | Whether the trustline is currently active |
| `established_date` | DATETIME | When the relationship was first established |
| `last_activity` | DATETIME | Last time a transaction occurred |
| `notes` | TEXT | Free-form notes about the relationship |

#### Key Constraints

1. **User Ordering**: `user_a_id < user_b_id` prevents duplicate relationships
2. **Unique Pair**: Only one trustline per user pair
3. **Self-Reference Prevention**: `user_a_id != user_b_id`
4. **Monetary Precision**: All amounts use DECIMAL(10,2) for currency accuracy

### trustline_transactions

Records all movements of credit through the trustline network.

```sql
CREATE TABLE trustline_transactions (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  -- Core transaction data
  trustline_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  description TEXT,
  
  -- Related entities
  originating_request_id BIGINT,
  order_id BIGINT,
  
  -- Payment routing (for multi-hop payments)
  path_info JSON,
  
  -- Transaction metadata
  transaction_type VARCHAR(255) NOT NULL,
  initiated_by_id BIGINT NOT NULL,
  balance_after DECIMAL(10,2),
  is_reversed BOOLEAN DEFAULT false,
  
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  
  -- Indexes
  INDEX index_trustline_transactions_on_trustline_id (trustline_id),
  INDEX index_trustline_transactions_on_originating_request_id (originating_request_id),
  INDEX index_trustline_transactions_on_order_id (order_id),
  INDEX index_trustline_transactions_on_initiated_by_id (initiated_by_id),
  INDEX index_trustline_transactions_on_transaction_type (transaction_type),
  INDEX index_trustline_transactions_on_created_at (created_at),
  INDEX index_trustline_transactions_on_is_reversed (is_reversed),
  
  -- Foreign keys
  FOREIGN KEY (trustline_id) REFERENCES trustlines(id),
  FOREIGN KEY (originating_request_id) REFERENCES item_requests(id),
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (initiated_by_id) REFERENCES users(id)
);
```

#### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `trustline_id` | BIGINT | Reference to the affected trustline |
| `amount` | DECIMAL(10,2) | Transaction amount (always positive) |
| `description` | TEXT | Human-readable transaction description |
| `originating_request_id` | BIGINT | Optional link to triggering ItemRequest |
| `order_id` | BIGINT | Optional link to associated Order |
| `path_info` | JSON | Routing data for multi-hop payments |
| `transaction_type` | VARCHAR | Type: 'payment', 'settlement', 'adjustment', 'reversal' |
| `initiated_by_id` | BIGINT | User who initiated the transaction |
| `balance_after` | DECIMAL(10,2) | Trustline balance after this transaction |
| `is_reversed` | BOOLEAN | Whether this transaction has been reversed |

#### Transaction Types

| Type | Description |
|------|-------------|
| `payment` | Regular payment between users |
| `settlement` | External settlement (outside the app) |
| `adjustment` | Manual balance correction by admin |
| `reversal` | Reversal of a previous transaction |

## Relationships

### Entity Relationship Diagram

```
users
  ↓ (one-to-many via user_a_id)
trustlines
  ↓ (one-to-many via user_b_id)
users

trustlines
  ↓ (one-to-many)
trustline_transactions
  ↓ (many-to-one)
users (initiated_by)

trustline_transactions
  ↓ (many-to-one, optional)
item_requests (originating_request)

trustline_transactions
  ↓ (many-to-one, optional)
orders
```

### Key Relationships

1. **Trustlines ↔ Users**: Each trustline connects exactly two users
2. **Transactions ↔ Trustlines**: Each transaction affects exactly one trustline
3. **Transactions ↔ Users**: Each transaction is initiated by exactly one user
4. **Transactions ↔ ItemRequests**: Transactions can optionally link to item requests
5. **Transactions ↔ Orders**: Transactions can optionally link to orders

## Data Integrity

### Constraints

1. **Balance Consistency**: Trustline balance must equal sum of transaction effects
2. **User Ordering**: In trustlines, user_a_id < user_b_id always
3. **Positive Amounts**: Transaction amounts are always positive
4. **Valid Transaction Types**: Only predefined transaction types allowed

### Validation Rules

```ruby
# Trustline validations
validates :credit_limit_a_to_b, :credit_limit_b_to_a, :current_balance, 
          presence: true, numericality: true
validates :user_a_id, uniqueness: { scope: :user_b_id }
validate :different_users
validate :user_order_constraint

# Transaction validations  
validates :amount, presence: true, numericality: { greater_than: 0 }
validates :transaction_type, inclusion: { 
  in: %w[payment settlement adjustment reversal] 
}
validates :balance_after, presence: true, numericality: true
```

## Indexes for Performance

### Query Patterns and Indexes

1. **Find user's trustlines**: `INDEX (user_a_id), INDEX (user_b_id)`
2. **Find trustline between users**: `UNIQUE INDEX (user_a_id, user_b_id)`
3. **Active trustlines only**: `INDEX (is_active)`
4. **Transaction history**: `INDEX (created_at)`
5. **User's transactions**: `INDEX (initiated_by_id)`
6. **Item request payments**: `INDEX (originating_request_id)`

### Composite Indexes

```sql
-- For user transaction queries
CREATE INDEX idx_transactions_user_date 
ON trustline_transactions (initiated_by_id, created_at);

-- For trustline activity queries  
CREATE INDEX idx_trustlines_user_active 
ON trustlines (user_a_id, is_active);

CREATE INDEX idx_trustlines_user_b_active 
ON trustlines (user_b_id, is_active);
```

## Sample Data

### Example Trustline

```sql
INSERT INTO trustlines (
  user_a_id, user_b_id, 
  credit_limit_a_to_b, credit_limit_b_to_a,
  current_balance, is_active, established_date,
  notes, created_at, updated_at
) VALUES (
  1, 2,
  1000.00, 500.00,
  250.00, true, '2024-06-01 10:00:00',
  'Local producer relationship',
  NOW(), NOW()
);
```

### Example Transaction

```sql
INSERT INTO trustline_transactions (
  trustline_id, amount, description,
  transaction_type, initiated_by_id, balance_after,
  created_at, updated_at
) VALUES (
  1, 150.00, 'Payment for organic vegetables',
  'payment', 1, 250.00,
  NOW(), NOW()
);
```

## Migration History

### Key Migrations

1. **20250624085633_create_trustlines.rb**
   - Creates main trustlines table
   - Establishes user relationships and credit limits
   - Sets up balance tracking

2. **20250624100523_create_trustline_transactions.rb**
   - Creates transaction audit trail
   - Links to item requests and orders
   - Supports multi-hop payment routing

### Migration Commands

```bash
# Create the trustline tables
rails db:migrate

# Rollback if needed
rails db:rollback STEP=2

# Check migration status
rails db:migrate:status
```

## Backup and Recovery

### Critical Data

1. **Trustlines**: Core relationships and balances
2. **Transactions**: Complete audit trail (NEVER delete)
3. **User relationships**: Essential for system operation

### Backup Strategy

```sql
-- Backup trustlines and transactions
mysqldump -u user -p database_name trustlines trustline_transactions > mutual_credit_backup.sql

-- Restore
mysql -u user -p database_name < mutual_credit_backup.sql
```

### Data Validation Queries

```sql
-- Check balance consistency
SELECT t.id, t.current_balance,
       SUM(CASE 
         WHEN tt.initiated_by_id = t.user_a_id THEN tt.amount
         ELSE -tt.amount 
       END) as calculated_balance
FROM trustlines t
LEFT JOIN trustline_transactions tt ON t.id = tt.trustline_id
WHERE tt.is_reversed = false
GROUP BY t.id
HAVING t.current_balance != COALESCE(calculated_balance, 0);

-- Check for orphaned transactions
SELECT COUNT(*) 
FROM trustline_transactions tt
LEFT JOIN trustlines t ON tt.trustline_id = t.id
WHERE t.id IS NULL;
```

## Performance Considerations

### Query Optimization

1. **Use appropriate indexes** for common query patterns
2. **Limit transaction history** queries with date ranges
3. **Eager load associations** when fetching trustlines with users
4. **Consider caching** user financial summaries for high-traffic scenarios

### Scaling Considerations

1. **Partition transactions table** by date for large datasets
2. **Archive old transactions** while preserving audit trail
3. **Consider read replicas** for financial summary queries
4. **Monitor query performance** and add indexes as needed 