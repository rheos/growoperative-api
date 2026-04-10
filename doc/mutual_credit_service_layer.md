# Mutual Credit Service Layer — Architecture

## Purpose

The mutual credit system is Growoperative's core differentiator. This document describes the architecture for how the React Native app (`growoperative-app/`) consumes credit and payment functionality through an **extraction-ready service layer** — designed so the underlying engine can be swapped from the current Rails API to an external mutual credit API or a blockchain without touching marketplace code.

## Current State (as of 2026-04-10)

- **Backend API:** Trustline endpoints are merged to `master` and live at `api.growoperative.app`. Full CRUD, direct payments, multi-hop routing, financial summaries.
- **RN app — core layer:** `src/core/trustlines/` is fully built: `CreditLedger` interface, `RailsCreditLedger` implementation, Redux slice, saga, selectors, hooks.
- **RN app — UI layer:** `src/ui/trustlines/` has components: `TrustlineScreen`, `TrustlineCard`, `CreateTrustlineModal`, `PaymentModal`, `PaymentPathView`, `TransactionHistory`.
- **Order flow:** `src/core/orders/` is empty (`.gitkeep` only). Settlement UI not yet built. See `growoperative-app/docs/claude/plans/01-order-flow-settlement.md`.

## Design Principle: The CreditLedger Extraction Boundary

The marketplace (items, orders, requests, dashboard) never calls credit APIs directly. All credit operations go through a single interface:

```
Marketplace code  →  CreditLedger interface  →  (implementation)
```

The interface is defined in `src/core/trustlines/credit-ledger.ts`. Implementations are swappable:

| Implementation | Transport | When |
|---------------|-----------|------|
| `RailsCreditLedger` | Axios → Rails API | Now (current) |
| `ExternalCreditLedger` | HTTP → external mutual credit API | When integrating with another MC project |
| `OnChainCreditLedger` | ethers.js / web3 → smart contracts | When moving to blockchain |

### What's behind the boundary

Everything the credit engine owns — the part that moves when you swap backends:

- **Trustline management** — CRUD for bilateral credit relationships
- **Payments** — direct and multi-hop, path finding (BFS routing)
- **Transaction history** — audit trail of all credit movements
- **Credit position queries** (future) — per-counterparty receivables/payables
- **Credit loop detection** (future) — finding cycles in the network graph where mutual debts cancel out
- **Event subscription** (future) — push notifications when loops close, balances change

### What stays in the app

- Redux slice, saga, selectors, hooks — app-specific glue
- Settlement UI (modals, order flow integration)
- Marketplace logic (items, orders, requests, dashboard)
- Notifications display

## File Structure

```
src/core/trustlines/
  credit-ledger.ts    # CreditLedger interface — THE extraction boundary
  service.ts          # RailsCreditLedger implements CreditLedger + singleton
  types.ts            # DTO types (CreateTrustlineParams, PaymentParams, etc.)
  slice.ts            # Redux Toolkit slice
  saga.ts             # Thin adapter: CreditLedger → Redux
  selectors.ts        # Memoized selectors
  hooks.ts            # React hooks for UI consumption
  index.ts            # Barrel exports
```

### Dependency Graph

```
credit-ledger.ts (interface, no deps)
       ↑
  service.ts (RailsCreditLedger implements it, depends on HttpClient)
       ↑
   saga.ts ───→ slice.ts ───→ selectors.ts ───→ hooks.ts
       │             ↑
       ↓             │
  notifications      └──── store/index.ts (registration)
  extractErrorMessage      store/rootSaga.ts (fork)
```

**Domain types** (`Trustline`, `TrustlineSummary`, `TrustlineTransaction`, `PaymentPath`) live in `src/core/types/models.ts` — shared across features. DTO types (`CreateTrustlineParams`, etc.) live in `src/core/trustlines/types.ts`.

## CreditLedger Interface

Defined in `credit-ledger.ts`. Current active methods:

| Method | Purpose |
|--------|---------|
| `listTrustlines()` | Get user's active trustlines |
| `getTrustline(id)` | Get specific trustline |
| `createTrustline(params)` | Create new trustline |
| `updateTrustline(id, params)` | Update credit limits or notes |
| `deactivateTrustline(id)` | Soft delete |
| `getSummary()` | Financial summary (aggregates) |
| `makeDirectPayment(trustlineId, params)` | Direct payment through specific trustline |
| `findPaymentPath(params)` | BFS routing for multi-hop payment |
| `executePathPayment(params)` | Execute multi-hop payment atomically |
| `getTransactions(trustlineId)` | Transaction history for a trustline |

### Planned future methods (commented placeholders in interface)

| Method | Purpose |
|--------|---------|
| `getReceivables()` | Per-counterparty "who owes me" breakdown |
| `getPayables()` | Per-counterparty "who I owe" breakdown |
| `findSettlementLoops()` | Detect cycles in the credit graph that can cancel mutual debts |
| `settleLoop(loopId)` | Execute a loop settlement, reducing balances for all participants |
| `onSettlementAvailable(cb)` | Push notification when a loop is detected involving the user |
| `onBalanceChanged(cb)` | Push notification when a trustline balance changes |

## RailsCreditLedger Implementation

`service.ts` — the current implementation. Key design decisions:

**Constructor injection:** Takes an `HttpClient` interface (which axios satisfies structurally), not a direct axios import. This makes the class testable with mocks and decoupled from the HTTP library.

```typescript
class RailsCreditLedger implements CreditLedger {
  constructor(private readonly http: HttpClient) {}
  // ...
}
```

**Singleton:** One line at the bottom of `service.ts` wires it to the app's axios instance:

```typescript
import api from '../services/api';
export const mutualCreditService: CreditLedger = new RailsCreditLedger(api);
```

The singleton is typed as `CreditLedger`, not `RailsCreditLedger`. All consumers (saga, hooks) program against the interface.

**No response mapping:** The Rails API responses match the TypeScript types in `core/types/models.ts` directly (both use snake_case). If a future implementation returns different shapes, it handles the mapping internally before returning `CreditLedger`-compatible types.

## Backend API Reference

All endpoints require JWT authentication. Base URL: `https://api.growoperative.app`.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/v1/trustlines` | List current user's active trustlines |
| `POST` | `/v1/trustlines` | Create new trustline |
| `GET` | `/v1/trustlines/:id` | Get trustline details |
| `PUT` | `/v1/trustlines/:id` | Update credit limits or notes |
| `DELETE` | `/v1/trustlines/:id` | Deactivate trustline (soft delete) |
| `GET` | `/v1/trustlines/summary` | Financial summary |
| `POST` | `/v1/trustlines/:id/payment` | Direct payment |
| `POST` | `/v1/trustlines/find_path` | Find multi-hop payment route (BFS) |
| `POST` | `/v1/trustlines/execute_path_payment` | Execute multi-hop payment atomically |
| `GET` | `/v1/trustlines/:id/transactions` | Transaction history for a trustline |

## Saga Pattern

The saga is a thin adapter — it calls `CreditLedger` methods and dispatches results into Redux. It owns error handling via `extractErrorMessage()` (which depends on axios, keeping that dependency out of the portable layer).

```typescript
// Saga calls the interface, not a specific implementation
const trustlines: Trustline[] = yield call(
  [mutualCreditService, mutualCreditService.listTrustlines],
);
yield put(trustlinesActions.fetchTrustlinesSuccess(trustlines));
```

## Extraction Strategy

When the credit engine moves to an external API or blockchain:

**Stays in the app (unchanged):**
- `credit-ledger.ts` — the interface
- `types.ts` — DTOs
- `slice.ts`, `saga.ts`, `selectors.ts`, `hooks.ts` — Redux/React glue
- All UI components

**Gets replaced:**
- `service.ts` — new class implements `CreditLedger` with different transport:
  - External API: new HTTP calls to their endpoints, response mapping in the class
  - Blockchain: ethers.js contract calls, event listeners for subscriptions

**The swap:**
```typescript
// Before (Rails)
import api from '../services/api';
export const mutualCreditService: CreditLedger = new RailsCreditLedger(api);

// After (external API)
import { externalClient } from '../services/external-credit';
export const mutualCreditService: CreditLedger = new ExternalCreditLedger(externalClient);

// After (blockchain)
import { provider } from '../services/web3';
export const mutualCreditService: CreditLedger = new OnChainCreditLedger(provider);
```

One line changes. Everything else — saga, slice, selectors, hooks, UI — works as before.

## Future: Credit Loop Detection

Credit loops are cycles in the network graph where mutual debts can cancel out. Example: Alice owes Bob $50, Bob owes Carol $30, Carol owes Alice $40 — a $30 loop exists.

### Where the intelligence lives

Loop detection is a **network-wide** operation — it needs visibility into the full graph, not just one user's trustlines. This means it naturally belongs in the backend/engine, not the app:

| Engine | How loops are found | How users are notified |
|--------|--------------------|-----------------------|
| Rails backend | Background job runs BFS/DFS cycle detection on the trustline graph | Creates notification records → app polls or receives push |
| External MC API | Their engine detects loops | Webhook to our server → push notification to app |
| Blockchain | Smart contract emits event when loop is settled | Event listener in `OnChainCreditLedger.onSettlementAvailable()` |

### App-side integration

When implemented, the app will:
1. Call `findSettlementLoops()` to show available opportunities in the UI
2. Let users review and approve a loop settlement (`settleLoop(loopId)`)
3. Subscribe to `onSettlementAvailable()` for real-time notification when new loops are found

The `CreditLedger` interface already has commented placeholder signatures for all three.

---

*Last updated: 2026-04-10*
