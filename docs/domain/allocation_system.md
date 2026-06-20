# Allocation system — engineering reference

Code: `systems/allocation_system.gd`. Owns who-owns-what on the graph and the three side-effects that make ownership "real" for the rest of the codebase.

## Four side-effects of allocation

Allocating a node `n` to entity `e` always does these four things:

1. **`n.owned_by = e`** — drives all visuals (owner-tint disk, addon visibility), `SkillNode.refill()` at owner turn-start, and per-node LocalStat rebinds (`get_local_stat()` reads its `entity_stat` from `owned_by.stat_board`).
2. **`e.navigator.mirror_add(n)`** — the EntityNavigator AStar mirror of *this entity's* subgraph picks up the node. Cut-vertex / islanding queries (`would_disconnect_from`, `nodes_islanded_by_removing`) read this mirror.
3. **For each `m` in `n.modifiers`: `e.stat_board.add_modifier(m)`** — pushes the node's intrinsic modifiers onto the entity's stat pipeline. DerivedStatModifiers are auto-bound to the board by `add_modifier`.
4. **`e.stat_board.skill_points.claim(1)`** (force_allocate only) — mints 1 SP into the `used` bucket, bumping max. Required so subsequent voluntary deallocation can refund into current without overflowing max and silently clamping away the SP. See `.claude/rules/stats-system.md` for the four-bucket SP model.

These four are exposed as the **`force_allocate(entity, node)`** primitive. It's the gating-free atom; everything else composes it. **Exception**: `allocate()` (the gated path) inlines steps 1–3 and substitutes `spend(1)` for step 4 — `spend` transfers current → used rather than minting, since the player paid for the allocation.

## The gated path: `allocate(node, entity)`

`allocate()` adds gameplay gates on top of `force_allocate`:

| Guard | Where | Condition |
|---|---|---|
| Target empty | `can_allocate` | `node.owned_by == null` |
| Has SP | `can_allocate` | `entity.stat_board.skill_points.current >= 1` |
| Adjacency | `can_allocate` | Target is adjacent to a node already owned by entity, **unless** entity owns nothing yet (the "first allocation is free of adjacency" core-placement rule) |
| Turn phase | (caller) | `turn_manager.can_allocate()` (i.e. `current_phase == EXPAND`) — gated in `PlayerInputController` |

On success: `skill_points.spend(1)` runs (transfers current → used), then steps 1–3 of the side-effects, then `allocated.emit(node, entity)`. Note: `allocate()` does **not** call `force_allocate()` — that would double-bump `used` (once via spend, once via claim). The side-effects are inlined.

## The gated path: `deallocate(node, entity)`

| Guard | Condition |
|---|---|
| Node is owned by entity | `node.owned_by == entity` |
| Node is not the core | `not node.is_core()` |
| Has DP | `entity.stat_board.deallocation_points.current >= 1` |
| No islanding | `entity.navigator.would_disconnect_from(node, entity.core_location)` returns false |
| Turn phase (caller) | `turn_manager.can_deallocate()` (i.e. `current_phase == CONTRACT`) |

On success: removes modifiers, mirror-removes from navigator, clears `owned_by`, then `deallocation_points.deplete(1)` + `skill_points.refund(1)`. Refund lands in `skill_points.current` (voluntary path).

## Forced deallocation: `force_deallocate(node)`

Called by `BattleSystem._on_node_depleted` (the cascade when a non-core node hits 0 HP). Skips every guard above (no DP cost, no would-disconnect check, no core-protection). Doesn't refund SP — the caller is responsible for `skill_points.wound(1)` instead, which puts the freed SP in the `wounded` bucket (heals back over time via `wound_heal_per_turn`). Also deducts 1 from `health` per cascaded node.

Returns the previous owner so the caller can chain wound + core-HP without re-reading `owned_by` (which is null after).

## When to use which

| Caller | Method | Why |
|---|---|---|
| Player click in EXPAND | `allocate` | Full gating; SP cost; signals |
| Player click in CONTRACT | `deallocate` | Full gating; DP cost; islanding check |
| Forced by attack | `force_deallocate` + caller-side `wound`/`health.deplete` | Bypass gates; route through wound bucket |
| Procgen setup | `force_allocate` (via `GameRoot.spawn_entity(name, color, core)`) | Bypass SP/adjacency; just plant the core |
| Procgen expansion | `force_allocate` directly | Random-walk expansion in dev sandboxes |
| Tests / scripted dev | `force_allocate` | Predictable setup, no resource bookkeeping |

**Never call `force_allocate` from gameplay code.** It mints free SP — using it for a player action quietly breaks the resource loop.

## Scene-authored ownership

Hand-authored levels (e.g. `dev_sandbox.tscn`) set `owned_by` directly in the scene tree, bypassing both `allocate` and `force_allocate`. `AllocationSystem.register_scene_authored_ownership()` walks the graph at `GameRoot._ready` (before `_setup_level`) and calls `claim(1)` per pre-owned node, so the entity's `used` bucket matches the node count. Procgen runs *after* this walk and registers via `force_allocate` directly — no double-counting.

## Optional dependencies

`graph` and `navigator` exports are optional. Without `graph`, adjacency is skipped (any unowned node can be allocated). Without `entity.navigator`, mirror updates and islanding checks are skipped. SP / DP gating still runs. This keeps headless tests and the spell playground working without standing up a full level.

## Signals

- `allocated(node, entity)` — fires from `force_allocate` (hence from both `allocate` and `spawn_entity` via that path)
- `deallocated(node, previous_owner)` — fires from both `deallocate` and `force_deallocate`

Listeners (UI, VisionSystem) shouldn't need to distinguish voluntary from forced — the signal shape is identical; downstream logic that cares (e.g. wound vs refund) lives in the BattleSystem cascade handler.
