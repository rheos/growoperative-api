# Mutual Credit Service Layer — Frontend Architecture

## Purpose

Architecture plan for implementing mutual credit functionality in the React Native app (`growoperative-app/`) as a **self-contained, extractable service layer**. The goal is to consume the existing backend trustline API while keeping the mutual credit logic decoupled enough to be split into an independent service or SDK later.

## Current State

- **Backend API:** Trustline endpoints are merged to `master` and live at `api.growoperative.app`. Full CRUD, direct payments, multi-hop routing, financial summaries.
- **RN app:** Empty `src/core/trustlines/` and `src/ui/trustlines/` directories exist (Sprint 5 placeholder). The app uses Redux Toolkit + Redux-Saga with a feature-module pattern.
- **Legacy frontend (`platform/`):** Not affected. This plan is entirely within the new RN app codebase.

## Design Principle: Service-First Architecture

The existing app pattern has Redux sagas calling the axios API client directly:

```
Saga  →  api.get('/v1/...')  →  dispatch results to Redux
```

For mutual credit, we introduce a **service class** between the saga and HTTP layer:

```
Saga  →  MutualCreditService  →  HttpClient interface  →  (axios satisfies this)
```

The service class owns all API communication, request/response mapping, and business logic. The saga becomes a thin adapter that delegates to the service and dispatches results into Redux.

### Why This Matters for Extraction

Three files form the extraction boundary — they have **zero** Redux, React, or axios imports:

| File | What it contains | Dependencies |
|------|-----------------|--------------|
| `types.ts` | All TypeScript types (domain models, API shapes, DTOs) | None |
| `http-client.ts` | Portable `HttpClient` interface | None |
| `service.ts` | `MutualCreditService` class | Only `types.ts` + `http-client.ts` |

When extraction time comes, these three files move to an npm package as-is. The app-specific glue (Redux slice, saga, selectors, hooks) stays behind. The only coupling point is a single line that creates the service instance with the app's axios client.

## Backend API Reference

All endpoints require JWT authentication. Base path: `/v1/trustlines`.

### Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/trustlines` | List current user's active trustlines |
| `POST` | `/trustlines` | Create new trustline |
| `GET` | `/trustlines/:id` | Get trustline details |
| `PATCH` | `/trustlines/:id` | Update credit limits or notes |
| `DELETE` | `/trustlines/:id` | Deactivate trustline (soft delete) |
| `GET` | `/trustlines/summary` | Financial summary (balances, available credit) |
| `POST` | `/trustlines/:id/payment` | Direct payment through specific trustline |
| `POST` | `/trustlines/find_path` | Find multi-hop payment route (BFS) |
| `POST` | `/trustlines/execute_path_payment` | Execute multi-hop payment atomically |

### Response Shapes

**Trustline (list/show/create/update):**
```json
{
  "id": 1,
  "other_user": { "id": 2, "name": "alice" },
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

**Summary:**
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

**Direct Payment:**
```json
{
  "message": "Payment processed successfully",
  "new_balance": "450.00",
  "trustline": { /* full trustline object */ }
}
```

**Find Path:**
```json
{
  "path_found": true,
  "path": [
    { "id": 1, "name": "alice" },
    { "id": 3, "name": "charlie" },
    { "id": 5, "name": "eve" }
  ],
  "path_length": 2,
  "estimated_cost": "200.00"
}
```

**Execute Path Payment:**
```json
{
  "message": "Path payment executed successfully",
  "path": [ { "id": 1, "name": "alice" }, { "id": 3, "name": "charlie" }, { "id": 5, "name": "eve" } ],
  "amount": "200.00"
}
```

### Request Parameters

**Create trustline:** `{ other_user_id, my_credit_limit, their_credit_limit, notes? }`

**Update trustline:** `{ credit_limit_a_to_b?, credit_limit_b_to_a?, notes? }`

**Direct payment:** `{ amount, description, originating_request_id? }`

**Find path:** `{ to_user_id, amount, max_hops? }`

**Execute path payment:** `{ to_user_id, amount, description, max_hops?, originating_request_id? }`

## File Structure

All new files in `growoperative-app/src/core/trustlines/`:

```
src/core/trustlines/
  types.ts              # Domain models, API shapes, DTOs (no deps)
  http-client.ts        # Portable HttpClient interface (no deps)
  service.ts            # MutualCreditService class (deps: types, http-client only)
  slice.ts              # Redux Toolkit slice (deps: types)
  saga.ts               # Thin saga adapter (deps: service, slice, notifications)
  selectors.ts          # Memoized selectors (deps: slice, types)
  hooks.ts              # React hooks (deps: selectors, slice)
  index.ts              # Barrel exports
  __tests__/
    service.test.ts     # Service unit tests with mock HttpClient
    selectors.test.ts   # Selector tests
    slice.test.ts       # Reducer tests
```

### Dependency Graph

```
types.ts  ←─────────────────────────────────────────┐
    ↑                                                │
http-client.ts                                       │
    ↑                                                │
service.ts ──────────────────────────┐               │
    ↑                                │               │
saga.ts ───→ slice.ts ───→ selectors.ts ───→ hooks.ts
    │            ↑
    ↓            │
notifications    └──── store/index.ts (registration)
extractErrorMessage    store/rootSaga.ts (fork)
```

## Detailed Component Designs

### 1. HttpClient Interface (`http-client.ts`)

The extraction boundary. The service depends on this interface, not on axios. Axios is structurally compatible without an adapter.

```typescript
export interface HttpResponse<T> {
  data: T;
  status: number;
}

export interface HttpClient {
  get<T>(url: string, config?: { params?: Record<string, unknown> }): Promise<HttpResponse<T>>;
  post<T>(url: string, data?: unknown): Promise<HttpResponse<T>>;
  patch<T>(url: string, data?: unknown): Promise<HttpResponse<T>>;
  delete<T>(url: string): Promise<HttpResponse<T>>;
}
```

### 2. Type Definitions (`types.ts`)

Three categories, all in one file for self-containment:

**Domain models** (camelCase — used by Redux state and UI components):

```typescript
export interface TrustlineUser {
  id: number;
  name: string;
}

export interface Trustline {
  id: number;
  otherUser: TrustlineUser;
  myCreditLimit: number;
  theirCreditLimit: number;
  myAvailableCredit: number;
  currentBalance: number;
  isActive: boolean;
  establishedDate: string;
  lastActivity: string | null;
  notes: string | null;
}

export interface RecentTransaction {
  id: number;
  amount: number;
  description: string;
  transactionType: string;
  createdAt: string;
  balanceAfter: number;
  isReversed: boolean;
}

export interface TrustlineSummary {
  totalTrustlines: number;
  totalCreditOwed: number;
  totalCreditOwedToMe: number;
  netCreditPosition: number;
  availableCredit: number;
  recentTransactions: RecentTransaction[];
}

export interface PaymentResult {
  message: string;
  newBalance: number;
  trustline: Trustline;
}

export interface PathNode {
  id: number;
  name: string;
}

export interface PathResult {
  pathFound: boolean;
  path: PathNode[];
  pathLength: number;
  estimatedCost: number;
}

export interface PathPaymentResult {
  message: string;
  path: PathNode[];
  amount: number;
}
```

**API response shapes** (snake_case — match backend exactly, used only inside the service):

```typescript
export interface ApiTrustline {
  id: number;
  other_user: { id: number; name: string };
  my_credit_limit: string;
  their_credit_limit: string;
  my_available_credit: string;
  current_balance: string;
  is_active: boolean;
  established_date: string;
  last_activity: string | null;
  notes: string | null;
}

export interface ApiRecentTransaction {
  id: number;
  amount: string;
  description: string;
  transaction_type: string;
  created_at: string;
  balance_after: string;
  is_reversed: boolean;
}

export interface ApiSummary {
  total_trustlines: number;
  total_credit_owed: string;
  total_credit_owed_to_me: string;
  net_credit_position: string;
  available_credit: string;
  recent_transactions: ApiRecentTransaction[];
}

export interface ApiPaymentResult {
  message: string;
  new_balance: string;
  trustline: ApiTrustline;
}

export interface ApiPathResult {
  path_found: boolean;
  path: Array<{ id: number; name: string }>;
  path_length: number;
  estimated_cost: string;
}

export interface ApiPathPaymentResult {
  message: string;
  path: Array<{ id: number; name: string }>;
  amount: string;
}
```

**DTOs** (camelCase — service method parameters):

```typescript
export interface CreateTrustlineParams {
  otherUserId: number;
  myCreditLimit: number;
  theirCreditLimit: number;
  notes?: string;
}

export interface UpdateTrustlineParams {
  myCreditLimit?: number;
  theirCreditLimit?: number;
  notes?: string;
}

export interface DirectPaymentParams {
  amount: number;
  description: string;
  originatingRequestId?: number;
}

export interface FindPathParams {
  toUserId: number;
  amount: number;
  maxHops?: number;
}

export interface ExecutePathPaymentParams {
  toUserId: number;
  amount: number;
  description: string;
  maxHops?: number;
  originatingRequestId?: number;
}
```

### 3. MutualCreditService (`service.ts`)

The core portable class. Zero imports from Redux, React, or axios.

```typescript
import type { HttpClient } from './http-client';
import type {
  Trustline, TrustlineSummary, PaymentResult, PathResult, PathPaymentResult,
  CreateTrustlineParams, UpdateTrustlineParams, DirectPaymentParams,
  FindPathParams, ExecutePathPaymentParams,
  ApiTrustline, ApiSummary, ApiPaymentResult, ApiPathResult, ApiPathPaymentResult,
} from './types';

export class MutualCreditService {
  constructor(private readonly http: HttpClient) {}

  // --- Private mappers (snake_case API → camelCase domain) ---

  private mapTrustline(api: ApiTrustline): Trustline { /* ... */ }
  private mapTransaction(api: ApiRecentTransaction): RecentTransaction { /* ... */ }
  private mapSummary(api: ApiSummary): TrustlineSummary { /* ... */ }
  private mapPaymentResult(api: ApiPaymentResult): PaymentResult { /* ... */ }
  private mapPathResult(api: ApiPathResult): PathResult { /* ... */ }

  // --- Queries ---

  async listTrustlines(): Promise<Trustline[]> {
    const response = await this.http.get<ApiTrustline[]>('/v1/trustlines');
    return response.data.map((t) => this.mapTrustline(t));
  }

  async getTrustline(id: number): Promise<Trustline> {
    const response = await this.http.get<ApiTrustline>(`/v1/trustlines/${id}`);
    return this.mapTrustline(response.data);
  }

  async getSummary(): Promise<TrustlineSummary> {
    const response = await this.http.get<ApiSummary>('/v1/trustlines/summary');
    return this.mapSummary(response.data);
  }

  async findPath(params: FindPathParams): Promise<PathResult> {
    const response = await this.http.post<ApiPathResult>('/v1/trustlines/find_path', {
      to_user_id: params.toUserId,
      amount: params.amount,
      ...(params.maxHops !== undefined && { max_hops: params.maxHops }),
    });
    return this.mapPathResult(response.data);
  }

  // --- Mutations ---

  async createTrustline(params: CreateTrustlineParams): Promise<Trustline> {
    const response = await this.http.post<ApiTrustline>('/v1/trustlines', {
      other_user_id: params.otherUserId,
      my_credit_limit: params.myCreditLimit,
      their_credit_limit: params.theirCreditLimit,
      ...(params.notes && { notes: params.notes }),
    });
    return this.mapTrustline(response.data);
  }

  async updateTrustline(id: number, params: UpdateTrustlineParams): Promise<Trustline> {
    const body: Record<string, unknown> = {};
    if (params.myCreditLimit !== undefined) body.credit_limit_a_to_b = params.myCreditLimit;
    if (params.theirCreditLimit !== undefined) body.credit_limit_b_to_a = params.theirCreditLimit;
    if (params.notes !== undefined) body.notes = params.notes;
    const response = await this.http.patch<ApiTrustline>(`/v1/trustlines/${id}`, body);
    return this.mapTrustline(response.data);
  }

  async deactivateTrustline(id: number): Promise<void> {
    await this.http.delete(`/v1/trustlines/${id}`);
  }

  async makeDirectPayment(trustlineId: number, params: DirectPaymentParams): Promise<PaymentResult> {
    const response = await this.http.post<ApiPaymentResult>(
      `/v1/trustlines/${trustlineId}/payment`,
      {
        amount: params.amount,
        description: params.description,
        ...(params.originatingRequestId && { originating_request_id: params.originatingRequestId }),
      },
    );
    return this.mapPaymentResult(response.data);
  }

  async executePathPayment(params: ExecutePathPaymentParams): Promise<PathPaymentResult> {
    const response = await this.http.post<ApiPathPaymentResult>(
      '/v1/trustlines/execute_path_payment',
      {
        to_user_id: params.toUserId,
        amount: params.amount,
        description: params.description,
        ...(params.maxHops !== undefined && { max_hops: params.maxHops }),
        ...(params.originatingRequestId && { originating_request_id: params.originatingRequestId }),
      },
    );
    return {
      message: response.data.message,
      path: response.data.path,
      amount: parseFloat(response.data.amount as unknown as string),
    };
  }
}
```

**Singleton instantiation** — the single coupling point to the app:

```typescript
// This is the only line that ties the service to the app's axios instance.
// Delete this line when extracting to an SDK.
import api from '../services/api';
export const mutualCreditService = new MutualCreditService(api);
```

### 4. Redux Slice (`slice.ts`)

Follows the contacts slice pattern exactly.

```typescript
interface TrustlinesState {
  trustlines: Trustline[];
  summary: TrustlineSummary | null;
  pathResult: PathResult | null;
  loading: boolean;
  submitting: boolean;
  error: string | null;
}
```

**Actions:**

| Action | Reducer behavior | Saga behavior |
|--------|-----------------|---------------|
| `fetchRequest` | `loading = true, error = null` | Calls `service.listTrustlines()` |
| `fetchSuccess(Trustline[])` | Sets `trustlines`, `loading = false` | — |
| `fetchFailure(string)` | Sets `error`, `loading = false` | — |
| `fetchSummaryRequest` | `loading = true` | Calls `service.getSummary()` |
| `fetchSummarySuccess(TrustlineSummary)` | Sets `summary`, `loading = false` | — |
| `createRequest(CreateTrustlineParams)` | Empty (saga trigger) | Calls `service.createTrustline()` |
| `createSuccess(Trustline)` | Prepends to `trustlines` | — |
| `updateRequest({id, params})` | Empty (saga trigger) | Calls `service.updateTrustline()` |
| `updateSuccess(Trustline)` | Replaces in `trustlines` by id | — |
| `deactivateRequest(number)` | Empty (saga trigger) | Calls `service.deactivateTrustline()` |
| `removeLocal(number)` | Filters out by id | — |
| `paymentRequest({trustlineId, params})` | Empty (saga trigger) | Calls `service.makeDirectPayment()` |
| `paymentSuccess(PaymentResult)` | Updates trustline in list | — |
| `findPathRequest(FindPathParams)` | `loading = true` | Calls `service.findPath()` |
| `findPathSuccess(PathResult)` | Sets `pathResult` | — |
| `clearPathResult` | Sets `pathResult = null` | — |
| `executePathPaymentRequest(...)` | Empty (saga trigger) | Calls `service.executePathPayment()` |
| `executePathPaymentSuccess` | Clears path | — |
| `setSubmitting(boolean)` | Sets `submitting` | — |
| `clear()` | Resets to `initialState` | — |

### 5. Saga (`saga.ts`)

Thin adapter. Each saga function:
1. Calls `yield call([mutualCreditService, mutualCreditService.method], ...args)`
2. Dispatches success action with result
3. On error: `extractErrorMessage(error, 'fallback')` + `notificationActions.show()`

Uses `[obj, obj.method]` call syntax to preserve `this` binding on the service instance.

Example pattern:

```typescript
function* fetchTrustlinesSaga() {
  try {
    const trustlines: Trustline[] = yield call(
      [mutualCreditService, mutualCreditService.listTrustlines],
    );
    yield put(trustlinesActions.fetchSuccess(trustlines));
  } catch (error: unknown) {
    const message = extractErrorMessage(error, 'Failed to load trustlines');
    yield put(trustlinesActions.fetchFailure(message));
    yield put(notificationActions.show({ type: 'error', message }));
  }
}

function* createTrustlineSaga(action: PayloadAction<CreateTrustlineParams>) {
  try {
    yield put(trustlinesActions.setSubmitting(true));
    const trustline: Trustline = yield call(
      [mutualCreditService, mutualCreditService.createTrustline],
      action.payload,
    );
    yield put(trustlinesActions.createSuccess(trustline));
    yield put(notificationActions.show({ type: 'success', message: 'Trustline created' }));
  } catch (error: unknown) {
    const message = extractErrorMessage(error, 'Failed to create trustline');
    yield put(notificationActions.show({ type: 'error', message }));
  } finally {
    yield put(trustlinesActions.setSubmitting(false));
  }
}
```

**Root watcher** uses `takeLatest` for all actions (prevents duplicate concurrent requests).

### 6. Selectors (`selectors.ts`)

Memoized with `createSelector`. Factory selectors for parameterized lookups.

| Selector | Input | Output |
|----------|-------|--------|
| `selectTrustlines` | state | `Trustline[]` |
| `selectTrustlinesLoading` | state | `boolean` |
| `selectTrustlinesError` | state | `string \| null` |
| `selectTrustlinesSubmitting` | state | `boolean` |
| `selectSummary` | state | `TrustlineSummary \| null` |
| `selectPathResult` | state | `PathResult \| null` |
| `selectActiveTrustlines` | trustlines | filtered `isActive === true` |
| `selectTrustlineById(id)` | trustlines | single `Trustline \| undefined` |
| `selectTrustlineByUserId(userId)` | trustlines | find by `otherUser.id` |
| `selectNetPosition` | summary | `number` (from `netCreditPosition`) |
| `selectTotalAvailableCredit` | summary | `number` (from `availableCredit`) |

### 7. Hooks (`hooks.ts`)

Wrap dispatch + selectors for UI consumption.

**`useTrustlines()`** — primary hook:
- Returns: `{ trustlines, loading, error, submitting, summary, pathResult }`
- Actions: `{ fetch, fetchSummary, create, update, deactivate, makePayment, findPath, executePathPayment, clearPath }`

**`useTrustline(id)`** — single trustline by relationship ID:
- Uses `useMemo` + `selectTrustlineById` factory

**`useTrustlineByUser(userId)`** — find trustline with a specific user:
- Uses `useMemo` + `selectTrustlineByUserId` factory

## Store Registration

Two minimal changes to existing files:

**`src/core/store/index.ts`** — add one import and one reducer key:
```typescript
import { trustlinesReducer } from '../trustlines/slice';
// In reducer map:
trustlines: trustlinesReducer,
```

**`src/core/store/rootSaga.ts`** — add one import and one fork:
```typescript
import { trustlinesSaga } from '../trustlines/saga';
// In all() array:
fork(trustlinesSaga),
```

No other existing files are modified. Trustline types stay in `src/core/trustlines/types.ts`, not in the shared `src/core/types/models.ts`.

## Extraction Strategy

When the mutual credit system needs to become a standalone SDK:

**Move out (zero changes needed):**
- `types.ts` — no app dependencies
- `http-client.ts` — no app dependencies
- `service.ts` — depends only on `types.ts` + `http-client.ts` (remove the singleton line at the bottom)

**Stays behind (app-specific adapter):**
- `slice.ts`, `saga.ts`, `selectors.ts`, `hooks.ts` — Redux/React glue
- The singleton instantiation moves to wherever the app wires things up
- SDK consumer provides their own `HttpClient` implementation (e.g., fetch-based, or their own axios instance)

**The service class never imports:**
- `axios` or any HTTP library directly
- Redux, React, or any UI framework
- `extractErrorMessage` or any app utility (error handling is the saga's job)
- Any other feature module (contacts, items, auth, etc.)

## Implementation Order

| Step | File | Rationale |
|------|------|-----------|
| 1 | `types.ts` | Everything depends on this |
| 2 | `http-client.ts` | Service depends on this |
| 3 | `service.ts` | Core logic, testable immediately with mock HttpClient |
| 4 | `slice.ts` | Redux state container |
| 5 | `saga.ts` | Wires service into Redux |
| 6 | `selectors.ts` | Memoized queries over slice state |
| 7 | `hooks.ts` | React interface for UI components |
| 8 | `index.ts` | Barrel exports |
| 9 | Store registration | 2-line edits to `store/index.ts` + `rootSaga.ts` |

## Testing Strategy

**Service tests (highest priority):**
- Provide a mock `HttpClient` returning canned API responses
- Verify snake_case → camelCase mapping is correct
- Verify correct endpoint URLs and request bodies
- Verify numeric string → number parsing

**Selector tests:**
- Provide mock state shapes
- Verify derived values (filtering, lookups)

**Reducer tests:**
- Verify state transitions for each action

**Commands:**
```bash
docker-compose exec app npm test                # Run all tests
docker-compose exec app npx tsc --noEmit        # Type check
```

## Design Decisions

**Why a class, not standalone functions?**
The service holds a reference to the HTTP client. A class makes this explicit via constructor injection. Standalone functions would either need the client passed to every call (noisy) or close over a module-level variable (implicit coupling, harder to test).

**Why not put types in shared `models.ts`?**
Self-containment for extraction. The `types.ts` file within the trustlines module is the single source of truth. Other modules that need trustline types import from `@core/trustlines/types`.

**Why doesn't the service catch errors?**
Because `extractErrorMessage()` imports from axios (checks `instanceof AxiosError`). Putting it in the service would add an axios dependency to the portable layer. Errors propagate naturally; the saga catches and formats them — matching the existing app pattern.

**Why a singleton at the bottom of `service.ts`?**
Keeps wiring minimal and localized. The class export is available for tests and SDK extraction. The singleton is a convenience for the saga. When extracting, delete one line.

---

*Last updated: 2026-04-09*
