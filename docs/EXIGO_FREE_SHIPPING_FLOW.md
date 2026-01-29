# Exigo Free Shipping Flow

## Overview

This document describes how the free shipping feature works for Yoli Exigo subscribers using Fluid callbacks.

## Architecture

The system uses two Fluid callbacks to track user authentication state and determine subscription eligibility:

1. **`cart_customer_logged_in`** - Triggered when a user logs into the cart
2. **`verify_email_success`** - Triggered when cart email is updated/verified

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ User logs in to cart                                         │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Fluid sends: cart_customer_logged_in callback               │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Droplet receives callback                                    │
│ - Extract: cart_id, email                                    │
│ - Query Exigo DB for subscription by email                   │
│ - Cache result: {cart_id: {email, has_subscription}}        │
│ - TTL: 30 minutes                                            │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Fluid sends: verify_email_success callback                   │
│ (triggered on email update)                                  │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Droplet receives callback                                    │
│ - Extract: cart_id, new_email                                │
│ - Read cached email for cart_id                              │
│                                                               │
│ IF new_email == cached_email:                                │
│   → Do nothing (keep subscription status)                    │
│ ELSE:                                                         │
│   → Clear cache for cart_id (remove subscription status)     │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ User proceeds to shipping selection                          │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Fluid calls: POST /callbacks/shipping_options               │
│ Payload includes: cart_id, items, ship_to                    │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Droplet processes request                                    │
│ - Read cache for cart_id                                     │
│ - IF has_subscription == true:                               │
│   → Filter shipping options to include subscriber-only       │
│   → Set price = $0 for free_for_subscribers options          │
│ - ELSE:                                                       │
│   → Exclude subscriber-only shipping options                 │
│ - Return available shipping methods                          │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Callbacks Controller

**Location**: `app/controllers/callbacks/cart_callbacks_controller.rb`

Handles two callback events:

#### `cart_customer_logged_in`
- Receives cart_id and email
- Queries Exigo database for active subscription
- Stores result in Redis cache with 30-minute TTL

#### `verify_email_success`
- Receives cart_id and updated email
- Compares with cached email
- If different or null: clears cached subscription status
- If same: maintains subscription status

### 2. Cart Session Service

**Location**: `app/services/cart_session_service.rb`

Manages cart-based session data in Redis:

```ruby
# Cache structure
{
  "cart_session:#{cart_id}:email" => "user@example.com",
  "cart_session:#{cart_id}:has_subscription" => true
}
```

**Methods**:
- `store_login(email, has_subscription)` - Stores user session data
- `update_email(new_email)` - Updates email if changed
- `has_active_subscription?` - Checks subscription status
- `clear_subscription_status` - Removes subscription cache

**TTL**: 30 minutes

### 3. Exigo Subscription Service

**Location**: `app/services/exigo_subscription_service.rb`

Checks Exigo database for active subscriptions:

```ruby
# Query
SELECT CustomerID, Email
FROM CustomerSubscriptions cs
INNER JOIN Customers c ON cs.CustomerID = c.CustomerID
WHERE cs.SubscriptionID = ?
  AND cs.IsActive = 1
  AND c.Email = ?
```

**Connection**: TinyTDS (SQL Server)

### 4. Shipping Calculation Service

**Location**: `app/services/shipping_calculation_service.rb`

Filters and prices shipping options based on subscription status:

**Logic**:
1. Check cache for cart_id subscription status
2. If `has_active_subscription?`:
   - Include `free_for_subscribers` shipping options
   - Set price = $0 for these options
3. If no subscription:
   - Exclude `free_for_subscribers` shipping options
4. Return available shipping methods

## Configuration

### Company Settings

**Location**: `companies.settings` (JSONB column)

```json
{
  "exigo_db_server": "server.database.windows.net",
  "exigo_db_name": "ExigoDB",
  "exigo_db_user": "readonly_user",
  "exigo_db_password": "encrypted_password",
  "exigo_subscription_id": "9",
  "free_shipping_for_subscribers": true
}
```

### Shipping Option Flag

**Table**: `shipping_options`
**Column**: `free_for_subscribers` (boolean)

When `true`, this shipping method:
- Only appears for users with active Exigo subscription
- Is FREE ($0.00) for subscribers
- Hidden from non-subscribers

## Edge Cases

### 1. User Logs Out
- Cache expires after 30 minutes
- On next shipping request, subscriber-only options won't appear

### 2. Email Changed After Login
- `verify_email_success` callback clears subscription status
- User loses free shipping until they log in again

### 3. Subscription Expires During Checkout
- Cache still shows `has_subscription = true` for up to 30 minutes
- Next login will refresh with current status

### 4. Multiple Carts for Same User
- Each cart_id has independent cache
- User can have active subscription in multiple carts simultaneously

## Routes

```ruby
namespace :callbacks do
  post 'cart_customer_logged_in', to: 'cart_callbacks#logged_in'
  post 'verify_email_success', to: 'cart_callbacks#email_verified'
end
```

## Testing

### Test Cart Customer Login
```bash
curl -X POST http://localhost:3000/callbacks/cart_customer_logged_in \
  -H "Content-Type: application/json" \
  -d '{
    "cart": {
      "id": 123,
      "email": "subscriber@example.com"
    }
  }'
```

### Test Email Verification
```bash
curl -X POST http://localhost:3000/callbacks/verify_email_success \
  -H "Content-Type: application/json" \
  -d '{
    "cart": {
      "id": 123,
      "email": "newemail@example.com"
    }
  }'
```

### Check Shipping Options
```bash
curl -X POST http://localhost:3000/callbacks/shipping_options \
  -H "Content-Type: application/json" \
  -d '{
    "cart": {
      "id": 123,
      "company": {"id": 1},
      "ship_to": {
        "country_code": "US",
        "state": "VA"
      },
      "items": []
    }
  }'
```

## Security Considerations

1. **Database Credentials**: Stored encrypted in JSONB settings
2. **Read-Only Access**: Exigo database user has read-only permissions
3. **Cache Expiration**: 30-minute TTL prevents stale subscription data
4. **Email Validation**: Email changes trigger cache invalidation

## Performance

- **Cache Hit**: ~1ms to check subscription status
- **Cache Miss + DB Query**: ~100-200ms (depending on Exigo DB latency)
- **Query Caching**: Results cached for 30 minutes per cart

## Monitoring

Key metrics to monitor:
- Exigo database connection failures
- Cache hit/miss ratio
- Callback processing time
- Subscription query latency
