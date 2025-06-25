# Trustlines API Reference

Complete API documentation for the mutual credit system endpoints.

## Base URL

All trustline endpoints are under `/api/v1/trustlines`

## Authentication

All endpoints require authentication. Include the authorization header:

```
Authorization: Bearer <your_jwt_token>
```

## Endpoints Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/trustlines` | List all user's trustlines |
| POST | `/trustlines` | Create new trustline |
| GET | `/trustlines/:id` | Show specific trustline |
| PATCH | `/trustlines/:id` | Update trustline |
| DELETE | `/trustlines/:id` | Deactivate trustline |
| GET | `/trustlines/summary` | Financial summary |
| POST | `/trustlines/:id/payment` | Direct payment |
| POST | `/trustlines/find_path` | Find payment path |
| POST | `/trustlines/execute_path_payment` | Execute multi-hop payment |

---

## CRUD Operations

### List Trustlines

Lists all active trustlines for the current user.

**Request:**
```http
GET /api/v1/trustlines
```

**Response:**
```json
[
  {
    "id": 1,
    "other_user": {
      "id": 2,
      "name": "Alice Smith"
    },
    "my_credit_limit": "1000.00",
    "their_credit_limit": "500.00",
    "my_available_credit": "700.00",
    "current_balance": "300.00",
    "is_active": true,
    "established_date": "2024-06-01T10:00:00Z",
    "last_activity": "2024-06-15T14:30:00Z",
    "notes": "Local producer relationship"
  }
]
```

### Create Trustline

Creates a new trustline between current user and another user.

**Request:**
```http
POST /api/v1/trustlines
Content-Type: application/json

{
  "other_user_id": 2,
  "my_credit_limit": "1000.00",
  "their_credit_limit": "500.00",
  "notes": "Local producer relationship"
}
```

**Response:**
```json
{
  "id": 1,
  "other_user": {
    "id": 2,
    "name": "Alice Smith"
  },
  "my_credit_limit": "1000.00",
  "their_credit_limit": "500.00",
  "my_available_credit": "1000.00",
  "current_balance": "0.00",
  "is_active": true,
  "established_date": "2024-06-24T10:00:00Z",
  "last_activity": null,
  "notes": "Local producer relationship"
}
```

### Show Trustline

Shows details of a specific trustline.

**Request:**
```http
GET /api/v1/trustlines/1
```

**Response:**
```json
{
  "id": 1,
  "other_user": {
    "id": 2,
    "name": "Alice Smith"
  },
  "my_credit_limit": "1000.00",
  "their_credit_limit": "500.00",
  "my_available_credit": "700.00",
  "current_balance": "300.00",
  "is_active": true,
  "established_date": "2024-06-01T10:00:00Z",
  "last_activity": "2024-06-15T14:30:00Z",
  "notes": "Local producer relationship"
}
```

### Update Trustline

Updates credit limits or notes for an existing trustline.

**Request:**
```http
PATCH /api/v1/trustlines/1
Content-Type: application/json

{
  "credit_limit_a_to_b": "1200.00",
  "credit_limit_b_to_a": "600.00",
  "notes": "Updated credit limits after review"
}
```

**Response:**
```json
{
  "id": 1,
  "other_user": {
    "id": 2,
    "name": "Alice Smith"
  },
  "my_credit_limit": "1200.00",
  "their_credit_limit": "600.00",
  "my_available_credit": "900.00",
  "current_balance": "300.00",
  "is_active": true,
  "established_date": "2024-06-01T10:00:00Z",
  "last_activity": "2024-06-15T14:30:00Z",
  "notes": "Updated credit limits after review"
}
```

### Deactivate Trustline

Deactivates a trustline (soft delete to preserve history).

**Request:**
```http
DELETE /api/v1/trustlines/1
```

**Response:**
```json
{
  "message": "Trustline deactivated successfully"
}
```

---

## Financial Summary

### Get Summary

Provides comprehensive financial summary for current user.

**Request:**
```http
GET /api/v1/trustlines/summary
```

**Response:**
```json
{
  "total_trustlines": 3,
  "total_credit_owed": "450.00",
  "total_credit_owed_to_me": "200.00",
  "net_credit_position": "-250.00",
  "available_credit": "2800.00",
  "recent_transactions": [
    {
      "id": 15,
      "amount": "150.00",
      "description": "Payment for organic vegetables",
      "transaction_type": "payment",
      "created_at": "2024-06-24T14:30:00Z",
      "balance_after": "300.00",
      "is_reversed": false
    }
  ]
}
```

---

## Payment Processing

### Direct Payment

Processes a direct payment through a specific trustline.

**Request:**
```http
POST /api/v1/trustlines/1/payment
Content-Type: application/json

{
  "amount": "150.00",
  "description": "Payment for organic vegetables",
  "originating_request_id": 42
}
```

**Response:**
```json
{
  "message": "Payment processed successfully",
  "new_balance": "450.00",
  "trustline": {
    "id": 1,
    "other_user": {
      "id": 2,
      "name": "Alice Smith"
    },
    "my_credit_limit": "1000.00",
    "their_credit_limit": "500.00",
    "my_available_credit": "550.00",
    "current_balance": "450.00",
    "is_active": true,
    "established_date": "2024-06-01T10:00:00Z",
    "last_activity": "2024-06-24T14:30:00Z",
    "notes": "Local producer relationship"
  }
}
```

---

## Network Payment Routing

### Find Payment Path

Finds a payment path through the trustline network.

**Request:**
```http
POST /api/v1/trustlines/find_path
Content-Type: application/json

{
  "to_user_id": 5,
  "amount": "200.00",
  "max_hops": 3
}
```

**Response:**
```json
{
  "path_found": true,
  "path": [
    {"id": 1, "name": "Current User"},
    {"id": 3, "name": "Bob Johnson"},
    {"id": 5, "name": "Carol Williams"}
  ],
  "path_length": 2,
  "estimated_cost": "200.00"
}
```

### Execute Multi-hop Payment

Executes a multi-hop payment through the trustline network.

**Request:**
```http
POST /api/v1/trustlines/execute_path_payment
Content-Type: application/json

{
  "to_user_id": 5,
  "amount": "200.00",
  "description": "Payment for specialty items",
  "max_hops": 3,
  "originating_request_id": 58
}
```

**Response:**
```json
{
  "message": "Path payment executed successfully",
  "path": [
    {"id": 1, "name": "Current User"},
    {"id": 3, "name": "Bob Johnson"},
    {"id": 5, "name": "Carol Williams"}
  ],
  "amount": "200.00"
}
```

---

## Error Responses

### Common Error Codes

| Code | Description |
|------|-------------|
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Authentication required |
| 403 | Forbidden - Access denied |
| 404 | Not Found - Resource doesn't exist |
| 422 | Unprocessable Entity - Validation errors |

### Error Response Format

```json
{
  "errors": [
    "Insufficient credit limit",
    "User not found"
  ]
}
```

### Specific Error Scenarios

**Insufficient Credit:**
```json
{
  "errors": ["Insufficient credit limit"]
}
```

**No Payment Path Found:**
```json
{
  "path_found": false,
  "message": "No payment path found within specified constraints"
}
```

**Trustline Not Found:**
```json
{
  "errors": ["Trustline not found"]
}
```

**Validation Errors:**
```json
{
  "errors": [
    "Amount must be greater than 0",
    "User B cannot be the same as User A"
  ]
}
```

---

## Rate Limits

Currently no rate limits are implemented, but consider implementing them for production use:

- **General API calls**: 1000 requests per hour per user
- **Payment operations**: 100 payments per hour per user
- **Path finding**: 200 requests per hour per user

## SDKs and Libraries

### JavaScript/Node.js Example

```javascript
const API_BASE = 'https://your-api.com/api/v1';
const token = 'your_jwt_token';

// Create trustline
async function createTrustline(otherUserId, myCreditLimit, theirCreditLimit) {
  const response = await fetch(`${API_BASE}/trustlines`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      other_user_id: otherUserId,
      my_credit_limit: myCreditLimit,
      their_credit_limit: theirCreditLimit
    })
  });
  
  return await response.json();
}

// Make payment
async function makePayment(trustlineId, amount, description) {
  const response = await fetch(`${API_BASE}/trustlines/${trustlineId}/payment`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      amount: amount,
      description: description
    })
  });
  
  return await response.json();
}
```

### Ruby Example

```ruby
require 'net/http'
require 'json'

class TrustlineAPI
  API_BASE = 'https://your-api.com/api/v1'
  
  def initialize(token)
    @token = token
  end
  
  def create_trustline(other_user_id, my_credit_limit, their_credit_limit)
    uri = URI("#{API_BASE}/trustlines")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request.body = {
      other_user_id: other_user_id,
      my_credit_limit: my_credit_limit,
      their_credit_limit: their_credit_limit
    }.to_json
    
    response = http.request(request)
    JSON.parse(response.body)
  end
  
  def make_payment(trustline_id, amount, description)
    uri = URI("#{API_BASE}/trustlines/#{trustline_id}/payment")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request.body = {
      amount: amount,
      description: description
    }.to_json
    
    response = http.request(request)
    JSON.parse(response.body)
  end
end
``` 