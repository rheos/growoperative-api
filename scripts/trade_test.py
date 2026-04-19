#!/usr/bin/env python3
"""
End-to-end trade test.

Drives a realistic sequence of user actions against the running backend via
HTTP — the same calls the app makes. Between every mutating action, asks the
backend /v1/debug/invariants whether data integrity still holds. First
violation aborts the run.

Run via bin/foaf-trade-test (which resets the DB first), or directly:
    python3 scripts/trade_test.py

Env overrides:
    TRADE_TEST_HOST       default http://localhost:3001
    TRADE_TEST_DELAY      seconds between browser-equivalent actions; default 2
    TRADE_TEST_VERBOSE    '1' to dump every request/response

Exits:
    0  all scenarios passed
    1  invariant violation
    2  API or setup error
"""

from __future__ import annotations

import json
import os
import sys
import time
import warnings
from dataclasses import dataclass, field
from typing import Any

# Silence the LibreSSL/urllib3 noise on stock macOS Python.
warnings.filterwarnings("ignore", message=".*LibreSSL.*")

import requests  # noqa: E402

HOST = os.environ.get("TRADE_TEST_HOST", "http://localhost:3001").rstrip("/")
DELAY = float(os.environ.get("TRADE_TEST_DELAY", "2"))
VERBOSE = os.environ.get("TRADE_TEST_VERBOSE", "") == "1"

# --- Tiny logging helpers ---------------------------------------------------


def header(msg: str) -> None:
    print(f"\n▶ {msg}")


def ok(msg: str) -> None:
    print(f"    ✓ {msg}")


def fail(msg: str) -> None:
    print(f"    ✗ {msg}")


def info(msg: str) -> None:
    print(f"      · {msg}")


# --- Exit helpers -----------------------------------------------------------


class SetupError(Exception):
    pass


class ApiError(Exception):
    pass


class InvariantError(Exception):
    def __init__(self, violations: list[dict], action: str):
        self.violations = violations
        self.action = action


# --- HTTP client ------------------------------------------------------------


@dataclass
class Client:
    # No Session: the backend reads JWT from cookie BEFORE the Authorization
    # header, so a persistent session pollutes identity across users. We pay
    # a small perf cost for per-request TCP; it's worth the correctness.
    tokens: dict[str, str] = field(default_factory=dict)  # user_name -> jwt
    active_user: str | None = None
    # Record of API failures that didn't abort the run (scenario try/except
    # blocks swallow them so a single failed action doesn't mask invariants).
    # If non-empty at exit, the script exits non-zero.
    api_errors: list[dict] = field(default_factory=list)

    # --- auth ---

    def login(self, user_name: str, user_id: int) -> str:
        if user_name in self.tokens:
            return self.tokens[user_name]
        resp = self._raw("POST", "/v1/demo/login", json={"user_id": user_id}, auth=False)
        token = resp["token"]
        self.tokens[user_name] = token
        return token

    def use(self, user_name: str) -> "Client":
        """Set the active user for subsequent calls."""
        self.active_user = user_name
        return self

    # --- HTTP verbs (all auth'd, delayed, logged) ---

    def get(self, path: str, params: dict | None = None) -> Any:
        return self._call("GET", path, params=params)

    def post(self, path: str, body: dict | None = None) -> Any:
        return self._call("POST", path, json=body)

    def put(self, path: str, body: dict | None = None) -> Any:
        return self._call("PUT", path, json=body)

    # --- internals ---

    def _call(self, method: str, path: str, **kw):
        if DELAY > 0:
            time.sleep(DELAY)
        return self._raw(method, path, auth=True, **kw)

    def _raw(self, method: str, path: str, auth: bool = True, **kw):
        url = f"{HOST}{path}"
        headers = {"Accept": "application/json"}
        if auth:
            if not self.active_user:
                raise ApiError(f"no active user for {method} {path}")
            token = self.tokens.get(self.active_user)
            if not token:
                raise ApiError(f"no token for {self.active_user} (login first)")
            headers["Authorization"] = f"Bearer {token}"
        if VERBOSE:
            info(f"{method} {path} as {self.active_user if auth else '-'}")
        resp = requests.request(method, url, headers=headers, **kw)
        if resp.status_code >= 400:
            preview = resp.text[:400]
            raise ApiError(f"{method} {path} -> {resp.status_code}: {preview}")
        if not resp.text:
            return {}
        try:
            return resp.json()
        except ValueError:
            return {"raw": resp.text}


# --- Invariant checker ------------------------------------------------------


def check_invariants(client: Client, after_action: str) -> None:
    """Hit /v1/debug/invariants and raise if anything is broken."""
    resp = requests.get(f"{HOST}/v1/debug/invariants", timeout=10)
    resp.raise_for_status()
    data = resp.json()
    if not data.get("passed"):
        raise InvariantError(data.get("violations", []), after_action)
    if VERBOSE:
        info(f"invariants OK after: {after_action}")


def check_foaf_shadow_health() -> None:
    """If shadow mode is on, refuse to run unless FOAF is reachable AND has
    at least one currency network. Without a network, every shadow op fails
    silently and the test passes while mirroring nothing — exactly the
    failure mode that prompted this check.
    """
    try:
        resp = requests.get(f"{HOST}/v1/debug/foaf/status", timeout=10)
        resp.raise_for_status()
        s = resp.json()
    except Exception as e:
        raise SetupError(f"FOAF status endpoint unreachable: {e}")

    if not s.get("shadow_mode"):
        info("FOAF shadow mode off — test will not mirror to FOAF (this is fine if intended)")
        return

    if not s.get("foaf_reachable"):
        raise SetupError(
            f"FOAF shadow_mode=true but FOAF is unreachable at {s.get('foaf_url')}. "
            "Refusing to run — every trustline op would silently drop."
        )

    if int(s.get("networks", 0)) < 1:
        raise SetupError(
            "FOAF shadow_mode=true and reachable, but no currency networks deployed. "
            "Every shadow op will fail with 'No network found on FOAF'. "
            "Run bin/foaf-reset-demo (which deploys the network) before retrying."
        )

    ok(f"FOAF shadow OK: networks={s['networks']} version={s.get('foaf_version')}")


# --- Graph + target discovery ----------------------------------------------


def fetch_demo_graph() -> tuple[dict[int, str], list[dict]]:
    """Returns (nodes_by_id={id: user_name}, all_edges).

    All edges are returned; consumers filter by edge['type'] ('relationship'
    for routing, 'trustline' for credit cycles)."""
    resp = requests.get(f"{HOST}/v1/demo/users", timeout=10)
    resp.raise_for_status()
    data = resp.json()
    nodes = {n["id"]: n.get("user_name") or n.get("name") or str(n["id"]) for n in data["nodes"]}
    return nodes, data["edges"]


def bfs_distances(source_id: int, edges: list[dict]) -> dict[int, int]:
    """BFS over relationship edges only (what the backend's own pathfinder uses)."""
    adj: dict[int, set[int]] = {}
    for e in edges:
        if e.get("type") != "relationship":
            continue
        a, b = e["source_id"], e["target_id"]
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    dist = {source_id: 0}
    queue = [source_id]
    while queue:
        u = queue.pop(0)
        for v in adj.get(u, set()):
            if v in dist:
                continue
            dist[v] = dist[u] + 1
            queue.append(v)
    return dist


def pick_endpoints(nodes: dict[int, str], edges: list[dict]) -> tuple[int, int, int]:
    """Two demo user IDs as far apart as possible. Returns (a_id, b_id, hops)."""
    best = (None, None, -1)
    for u in nodes:
        dist = bfs_distances(u, edges)
        for v, d in dist.items():
            if v == u or v not in nodes:
                continue
            if d > best[2]:
                best = (u, v, d)
    if best[0] is None:
        raise SetupError("could not find graph endpoints")
    return best  # type: ignore[return-value]


def find_targets(client: Client, actor_name: str, actor_id: int, edges: list[dict],
                 hops=(3, 4), limit: int = 3) -> list[dict]:
    """Find inventories owned by users at `hops` distance from `actor_id`.

    Uses the actor's own items view — this way we only see inventories the
    actor can actually see and request (auth-respecting)."""
    dist = bfs_distances(actor_id, edges)
    far_user_ids = {uid for uid, d in dist.items() if d in hops}
    # Same call the app's "around" column makes.
    resp = client.use(actor_name).get("/v1/items/around")
    # Response shape: { data: [items] } — each item has attributes incl. owner-id, name
    items = resp.get("data") if isinstance(resp, dict) else resp
    out = []
    for entry in items or []:
        attrs = entry.get("attributes", {})
        owner_id = int(attrs.get("owner-id") or attrs.get("user-id") or 0)
        if owner_id not in far_user_ids:
            continue
        out.append({
            "inventory_id": entry["id"],
            "owner_id": owner_id,
            "item_name": attrs.get("name"),
            "quantity": float(attrs.get("quantity") or 0),
            "hops": dist.get(owner_id),
        })
        if len(out) >= limit:
            break
    return out


# --- Debug queries we lean on (don't count as user actions) ----------------


def debug_user(user_name: str) -> dict:
    return requests.get(f"{HOST}/v1/debug/user/{user_name}", timeout=10).json()


def debug_requests(**filters) -> list[dict]:
    return requests.get(f"{HOST}/v1/debug/requests", params=filters, timeout=10).json().get("requests", [])


def pending_acceptable_requests() -> list[dict]:
    """Pending requests that are ready for the seller to accept (sent=true)."""
    data = requests.get(f"{HOST}/v1/debug/requests",
                        params={"status": "pending", "limit": 100}, timeout=10).json()
    # debug/requests may or may not expose `sent`; filter client-side best effort
    return [r for r in data.get("requests", []) if r.get("sent", True)]


# --- Scenarios --------------------------------------------------------------


def scenario_bilateral_pairs(client: Client, nodes: dict[int, str]) -> None:
    """Create directional request pairs between specific user pairs so the
    resulting credit settlements push balances around cycles in the trustline
    graph. These pairs are chosen because they have item inventory on both
    sides AND their paths cross enough of the graph to form cancellable loops
    once all orders settle via credit."""
    header("Scenario: bilateral requests (credloop seeds)")
    # The symmetric pairs exercise trade volume in both directions but cancel
    # out on each trustline. The trailing extra trades flow one-way to push
    # net debt around the 5-cycle (bob-peter-mary-arthur-bruce-bob) so that
    # CredloopRunner has something to detect. Specifically:
    #   - mary → barry routes via arthur→bruce→barry, adding mary→arthur debt
    #   - bruce → bob is a direct 1-hop, adding bruce→bob debt
    # Those two flips close the cycle counter-clockwise.
    pairs = [
        ("mary", "bruce", 2),
        ("bruce", "mary", 2),
        ("barry", "clark", 2),
        ("clark", "barry", 2),
        ("mary", "barry", 2),
        ("bruce", "bob", 2),
    ]
    for requester_name, target_name, count in pairs:
        req_id = _user_id_by_name(nodes, requester_name)
        tgt_id = _user_id_by_name(nodes, target_name)
        client.login(requester_name, req_id)
        resp = client.use(requester_name).get("/v1/items/around")
        data = resp.get("data", []) if isinstance(resp, dict) else resp
        target_invs = []
        for entry in data or []:
            attrs = entry.get("attributes", {})
            owner = int(attrs.get("owner-id") or attrs.get("user-id") or 0)
            if owner != tgt_id:
                continue
            qty = float(attrs.get("quantity") or 0)
            if qty <= 0:
                continue
            target_invs.append((entry["id"], attrs.get("name"), qty))
        if not target_invs:
            info(f"{requester_name} → {target_name}: no items visible")
            continue
        info(f"{requester_name} → {target_name}: {len(target_invs)} inventory option(s), requesting up to {count}")
        for inv_id, item_name, qty in target_invs[:count]:
            want = min(qty, 1.0)
            try:
                client.use(requester_name).post(
                    f"/v1/items/{inv_id}/requests",
                    {"request": {"quantity": want}},
                )
                info(f"  {requester_name} requested {want} of {item_name} (inv {inv_id}) from {target_name}")
                check_invariants(client, f"{requester_name}→{target_name} request {item_name}")
            except ApiError as e:
                msg = str(e)[:160]
                client.api_errors.append({"action": f"{requester_name}→{target_name} request {item_name}", "error": msg})
                info(f"  failed: {msg}")


def scenario_create_requests(client: Client, nodes: dict[int, str], edges: list[dict]) -> None:
    header("Scenario: create cross-graph requests")
    a_id, b_id, hops = pick_endpoints(nodes, edges)
    a_name, b_name = nodes[a_id], nodes[b_id]
    info(f"endpoints: {a_name} <—({hops} hops)—> {b_name}")

    for actor_id, actor_name in [(a_id, a_name), (b_id, b_name)]:
        client.login(actor_name, actor_id)
        targets = find_targets(client, actor_name, actor_id, edges, hops=(3, 4), limit=3)
        if not targets:
            info(f"{actor_name}: no 3-4 hop targets visible")
            continue
        info(f"{actor_name} requesting from {len(targets)} target(s)")
        for t in targets:
            qty = min(t["quantity"], 2.0)
            try:
                client.use(actor_name).post(
                    f"/v1/items/{t['inventory_id']}/requests",
                    {"request": {"quantity": qty}},
                )
                info(f"  {actor_name} requested {qty} of {t['item_name']} from user {t['owner_id']} ({t['hops']} hops)")
                check_invariants(client, f"{actor_name} requested {t['item_name']}")
            except ApiError as e:
                msg = str(e)[:160]
                client.api_errors.append({"action": f"{actor_name} request {t['item_name']}", "error": msg})
                info(f"  {actor_name} could not request {t['item_name']}: {msg}")


def scenario_accept_all(client: Client, nodes: dict[int, str]) -> None:
    header("Scenario: accept every pending request")
    # Loop until nothing pending is still acceptable.
    for attempt in range(20):  # bounded to avoid infinite loop
        data = requests.get(f"{HOST}/v1/debug/requests",
                            params={"status": "pending", "limit": 200}, timeout=10).json()
        requests_list = data.get("requests", [])
        # Only those that are `sent: true` are ready for the seller to accept.
        ready = [r for r in requests_list if r.get("sent") is True]
        if not ready:
            info(f"no more pending-accepted requests (attempts={attempt})")
            return
        info(f"round {attempt + 1}: {len(ready)} request(s) ready")
        for r in ready:
            seller_name = r["friend"]  # seller of the hop
            inventory_id = r["inventory_id"]
            request_id = r["item_request_id"]
            client.login(seller_name, _user_id_by_name(nodes, seller_name))
            try:
                client.use(seller_name).post(f"/v1/items/requests/{request_id}/accept")
                info(f"  {seller_name} accepted request {request_id} on inventory {inventory_id}")
                check_invariants(client, f"{seller_name} accepted request {request_id}")
            except ApiError as e:
                msg = str(e)[:160]
                client.api_errors.append({"action": f"accept req {request_id}", "error": msg})
                info(f"  accept failed for request {request_id}: {msg}")


def _ship_pass(client: Client, nodes: dict[int, str]) -> int:
    """Ship every shippable order once. Returns how many shipped."""
    shipped_count = 0
    for user_id, user_name in nodes.items():
        client.login(user_name, user_id)
        reserved = client.use(user_name).get("/v1/items/reserved")
        orders = _extract_orders(reserved)
        for o in orders:
            if str(o.get("friend_id")) != str(user_id):
                continue
            if o.get("order_status") not in ("pending", 0):
                continue
            if not o.get("is_ready"):
                continue
            try:
                client.use(user_name).put(
                    f"/v1/orders/{o['id']}",
                    {"order_action": {"action_name": "ship", "settlement_type": "credit"}},
                )
                info(f"  {user_name} shipped order {o['id']}")
                check_invariants(client, f"{user_name} shipped order {o['id']}")
                shipped_count += 1
            except ApiError as e:
                msg = str(e)[:160]
                client.api_errors.append({"action": f"ship order {o['id']}", "error": msg})
                info(f"  ship failed for order {o['id']}: {msg}")
    return shipped_count


def _sign_pass(client: Client, nodes: dict[int, str]) -> int:
    """Sign every shipped order once. Returns how many signed."""
    signed_count = 0
    for user_id, user_name in nodes.items():
        for o in _orders_for(client, user_name, user_id, status="shipped"):
            if str(o.get("user_id")) != str(user_id):
                continue
            try:
                client.use(user_name).put(
                    f"/v1/orders/{o['id']}",
                    {"order_action": {"action_name": "sign"}},
                )
                info(f"  {user_name} signed order {o['id']}")
                check_invariants(client, f"{user_name} signed order {o['id']}")
                signed_count += 1
            except ApiError as e:
                msg = str(e)[:160]
                client.api_errors.append({"action": f"sign order {o['id']}", "error": msg})
                info(f"  sign failed for order {o['id']}: {msg}")
    return signed_count


def scenario_ship_and_sign_until_stable(client: Client, nodes: dict[int, str]) -> None:
    """Sign a chain hop creates the next hop's order. So ship/sign must
    interleave until no more work is done in a full pass."""
    header("Scenario: ship + sign (iterative)")
    for iteration in range(10):
        shipped = _ship_pass(client, nodes)
        signed = _sign_pass(client, nodes)
        info(f"  round {iteration + 1}: shipped={shipped} signed={signed}")
        if shipped == 0 and signed == 0:
            info(f"  stable after {iteration + 1} round(s)")
            return
    info("  reached max iterations; something may be stuck")


def _orders_for(client: Client, user_name: str, user_id: int, status: str | None = None) -> list[dict]:
    """Use the /v1/orders index — same call the app makes for the Orders view."""
    client.login(user_name, user_id)
    params = {}
    if status:
        params["status"] = status
    resp = client.use(user_name).get("/v1/orders", params=params)
    data = resp.get("data", []) if isinstance(resp, dict) else []
    return data




def scenario_settle_credit(client: Client, nodes: dict[int, str]) -> None:
    header("Scenario: settle via credit")
    # Buyer responds agreeing to credit; seller executes. After shipping,
    # settlement_status='proposed' until the buyer responds. Run against all
    # orders (any status), filter on settlement_status + buyer identity.
    seen: set[int] = set()
    for user_id, user_name in nodes.items():
        for o in _orders_for(client, user_name, user_id):
            order_id = o.get("id")
            if order_id in seen:
                continue
            if str(o.get("user_id")) != str(user_id):
                continue
            if o.get("settlement_status") not in ("proposed",):
                continue
            seen.add(order_id)
            # Buyer: respond_settlement with credit (agreement).
            try:
                client.use(user_name).put(
                    f"/v1/orders/{order_id}",
                    {"order_action": {"action_name": "respond_settlement", "settlement_type": "credit"}},
                )
                info(f"  {user_name} agreed to credit on order {order_id}")
                check_invariants(client, f"{user_name} agreed settlement order {order_id}")
            except ApiError as e:
                msg = str(e)[:160]
                client.api_errors.append({"action": f"respond_settlement order {order_id}", "error": msg})
                info(f"  respond_settlement failed on {order_id}: {msg}")
                continue
            # Seller: execute_credit.
            seller_id = int(o.get("friend_id"))
            seller_name = nodes.get(seller_id)
            if not seller_name:
                continue
            try:
                client.login(seller_name, seller_id)
                client.use(seller_name).put(
                    f"/v1/orders/{order_id}",
                    {"order_action": {"action_name": "execute_credit"}},
                )
                info(f"  {seller_name} executed credit on order {order_id}")
                check_invariants(client, f"{seller_name} executed credit order {order_id}")
            except ApiError as e:
                msg = str(e)[:160]
                client.api_errors.append({"action": f"execute_credit order {order_id}", "error": msg})
                info(f"  execute_credit failed on {order_id}: {msg}")


# --- Scenario: rotational orders around a cycle (natural credloop seed) ----


def _find_cycle(edges: list[dict], edge_type: str, min_len: int = 4, max_len: int = 5,
                allowed_ids: set[int] | None = None) -> list[int] | None:
    """DFS for a simple cycle of length in [min_len, max_len] using edges of
    the given type. Returns [user_id, ..., user_id] with first repeated at end.

    When `allowed_ids` is given, only those users are traversed — useful for
    restricting to users who own inventory (rotational orders need every cycle
    member to have something to sell)."""
    adj: dict[int, set[int]] = {}
    for e in edges:
        if e.get("type") != edge_type:
            continue
        a, b = e["source_id"], e["target_id"]
        if allowed_ids is not None and (a not in allowed_ids or b not in allowed_ids):
            continue
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)

    def dfs(start, current, path, visited):
        if len(path) > max_len:
            return None
        for nxt in sorted(adj.get(current, set())):
            if nxt == start and len(path) >= min_len:
                return path + [start]
            if nxt in visited:
                continue
            result = dfs(start, nxt, path + [nxt], visited | {nxt})
            if result:
                return result
        return None

    for start in sorted(adj):
        result = dfs(start, start, [start], {start})
        if result:
            return result
    return None


def scenario_rotational_orders(client: Client, nodes: dict[int, str], edges: list[dict]) -> None:
    """Seed a credit loop the honest way: find a cycle in the relationship graph,
    then have each user place an order with the next one around the cycle.
    When those orders get accepted + shipped + signed + credit-settled in the
    main pipeline, balances flow rotationally around the cycle and CredloopRunner
    auto-cancels the excess. No direct trustline manipulation, no bypassing the
    app's normal flow — same calls the browser makes."""
    header("Scenario: rotational orders (natural credloop seed)")
    # Restrict cycle search to users who actually have inventory — a cycle
    # member with nothing to sell stalls the rotation mid-chain.
    sellers = _users_with_inventory()
    cycle = _find_cycle(edges, edge_type="relationship", min_len=4, max_len=5, allowed_ids=sellers)
    if not cycle:
        info("no relationship cycle among users-with-inventory — skipping")
        return
    names = [nodes[uid] for uid in cycle]
    info(f"cycle ({len(cycle) - 1} hops): {' → '.join(names)}")

    for i in range(len(cycle) - 1):
        buyer_id = cycle[i]
        seller_id = cycle[i + 1]
        buyer_name = nodes[buyer_id]
        seller_name = nodes[seller_id]
        # Find one inventory owned by seller that's visible to buyer.
        client.login(buyer_name, buyer_id)
        try:
            resp = client.use(buyer_name).get("/v1/items/around")
        except ApiError as e:
            client.api_errors.append({"action": f"{buyer_name} fetch around", "error": str(e)[:160]})
            continue
        items_data = resp.get("data", []) if isinstance(resp, dict) else resp
        inv_id = None
        item_name = None
        for entry in items_data or []:
            attrs = entry.get("attributes", {})
            owner = int(attrs.get("owner-id") or attrs.get("user-id") or 0)
            if owner != seller_id:
                continue
            if float(attrs.get("quantity") or 0) <= 0:
                continue
            inv_id = entry["id"]
            item_name = attrs.get("name")
            break
        if not inv_id:
            info(f"  {buyer_name} → {seller_name}: no inventory visible, skipping hop")
            continue
        # Use a large quantity so this rotational contribution dominates any
        # cross-graph chain flow that happens to hit the same trustlines. Without
        # enough rotational magnitude, one misaligned edge can keep the loop open.
        qty = 30.0
        try:
            client.use(buyer_name).post(
                f"/v1/items/{inv_id}/requests",
                {"request": {"quantity": qty}},
            )
            info(f"  {buyer_name} ordered {qty} of {item_name} from {seller_name}")
            check_invariants(client, f"{buyer_name} ordered from {seller_name} (rotation)")
        except ApiError as e:
            msg = str(e)[:160]
            client.api_errors.append({"action": f"{buyer_name} rotational order from {seller_name}", "error": msg})
            info(f"  order failed: {msg}")


def _users_with_inventory() -> set[int]:
    """Use each user's own /v1/debug/items/:username view to collect owners who
    have at least one available inventory. Cheap and auth-free."""
    # Fetch via demo/users once to get the list, then check each via a single
    # pass of /v1/items/around from an arbitrary demo login.
    # Simpler: use the /v1/debug/items/:username endpoint for each demo user
    # and collect owner IDs surfaced there (union of all perspectives).
    nodes, _ = fetch_demo_graph()
    owners: set[int] = set()
    # Seed from any one user's /items/around — owners shown there own inventory.
    anyone_id = next(iter(nodes))
    anyone_name = nodes[anyone_id]
    tmp = Client()
    tmp.login(anyone_name, anyone_id)
    resp = tmp.use(anyone_name).get("/v1/items/around")
    data = resp.get("data", []) if isinstance(resp, dict) else resp
    for entry in data or []:
        attrs = entry.get("attributes", {})
        owner = int(attrs.get("owner-id") or attrs.get("user-id") or 0)
        qty = float(attrs.get("quantity") or 0)
        if owner and qty > 0:
            owners.add(owner)
    # The seed user's own inventory won't appear in their around view — add them.
    owners.add(anyone_id)
    return owners


def check_credloop_fired(expect_min: int = 1) -> int:
    """Infer credloop cancellations from the app-side/FOAF reconciliation:
    any trustline where app_balance > foaf_balance reflects FOAF having
    cancelled part of the balance through a loop. Sum of diffs / 2 = total
    cancelled (each loop cancels two edges at min; we use the conservative
    max diff as a lower bound)."""
    header("Scenario: verify credit loop was detected + cancelled")
    try:
        reconcile = requests.get(f"{HOST}/v1/debug/foaf/reconcile", timeout=10).json()
    except Exception as e:
        info(f"reconcile fetch failed: {e}")
        return 0
    diffs = []
    for tl in reconcile.get("trustlines", []):
        app_bal = abs(float(tl["app"]["balance"]))
        foaf_bal = abs(float(tl["foaf"]["balance"]))
        if app_bal > foaf_bal + 0.01:
            diffs.append({
                "pair": f"{tl['user_a']}↔{tl['user_b']}",
                "app": app_bal,
                "foaf": foaf_bal,
                "cancelled": app_bal - foaf_bal,
            })
    if diffs:
        total = sum(d["cancelled"] for d in diffs)
        info(f"credloops cancelled ${total:.2f} across {len(diffs)} trustline(s):")
        for d in diffs:
            info(f"  {d['pair']}: app=${d['app']:.2f} foaf=${d['foaf']:.2f}  cancelled ${d['cancelled']:.2f}")
        return len(diffs)
    info(f"no credloop activity detected — {reconcile.get('summary', {}).get('matches', 0)} trustlines match exactly")
    if expect_min > 0:
        info(f"(expected at least {expect_min} credloop)")
    return 0


# --- Helpers ---------------------------------------------------------------


def _user_id_by_name(nodes: dict[int, str], name: str) -> int:
    for uid, n in nodes.items():
        if n == name:
            return uid
    raise SetupError(f"user {name!r} not in demo graph")


def _extract_orders(column_payload: Any) -> list[dict]:
    """The columns (reserved/shipped/requested) mix order-groups and item arrays.

    An order-group looks like {order: {...}, items: [...]}; arrays of items
    without an order are bare lists. We only return the order dicts."""
    if not column_payload:
        return []
    data = column_payload.get("data") if isinstance(column_payload, dict) else column_payload
    orders = []
    for entry in data or []:
        if isinstance(entry, dict) and "order" in entry:
            orders.append(entry["order"])
    return orders


# --- Entry -----------------------------------------------------------------


def print_violations(err: InvariantError) -> None:
    print("\n!!! INVARIANT VIOLATION !!!")
    print(f"Triggered by: {err.action}")
    for v in err.violations:
        print(f"  - [{v.get('name')}] {v.get('message')}")
        ctx = v.get("context")
        if ctx:
            print(f"    context: {json.dumps(ctx)[:400]}")


def main() -> int:
    print(f"  Host: {HOST}  Delay: {DELAY}s")
    client = Client()
    try:
        check_invariants(client, "baseline (post-reset)")
        ok("baseline invariants pass")
        check_foaf_shadow_health()
        nodes, edges = fetch_demo_graph()

        # Pass 1: the main stress flow.
        scenario_bilateral_pairs(client, nodes)
        scenario_create_requests(client, nodes, edges)
        scenario_accept_all(client, nodes)
        scenario_ship_and_sign_until_stable(client, nodes)
        scenario_settle_credit(client, nodes)
        # Pass 2: lay rotational credit on top so the final state has a one-way
        # flow around a cycle — giving CredloopRunner something to cancel.
        scenario_rotational_orders(client, nodes, edges)
        scenario_accept_all(client, nodes)
        scenario_ship_and_sign_until_stable(client, nodes)
        scenario_settle_credit(client, nodes)
        check_credloop_fired()

        if client.api_errors:
            print(f"\n=== {len(client.api_errors)} API ERROR(S) ===")
            for err in client.api_errors:
                print(f"  - {err['action']}: {err['error']}")
            print("\n=== INVARIANTS PASSED BUT API SURFACE FAILED ===")
            return 2
        print("\n=== ALL SCENARIOS PASSED ===")
        return 0
    except InvariantError as e:
        print_violations(e)
        return 1
    except (ApiError, SetupError) as e:
        print(f"\n!!! TEST FAILED !!!\n{e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
