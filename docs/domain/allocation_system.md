# Allocation system — engineering reference

Code: `systems/allocation_system.gd`. Owns who-owns-what on the graph and the four side-effects that make ownership "real" for the rest of the codebase.

## Four side-effects of allocation

Allocating a node `n` to entity `e` always does these four things:

1. **`n.owned_by = e`** — drives all visuals (owner-tint disk, addon visibility), `SkillNode.refill()` at owner turn-start, and node-local stat reads: `get_local_value(id)` merges the owner's board with the node's sparse `node_board` via `ModifierBins.compute(es.base_value, [es.bins, ns.bins])`, falling back to the node board alone (then the StatDef default) when unowned. There is no `LocalStat` class — see `.claude/rules/stats-system.md`.
2. **`e.navigator.mirror_add(n)`** — the EntityNavigator AStar mirror of *this entity's* subgraph picks up the node. Cut-vertex / islanding queries (`would_disconnect_from`, `nodes_islanded_by_removing`) read this mirror.
3. **For each `m` in `n.modifiers`: `e.stat_board.add_modifier(m)`** — pushes the node's intrinsic modifiers onto the entity's stat pipeline. DerivedStatModifiers are auto-bound to the board by `add_modifier`.
4. **`e.stat_board.skill_points.claim(1)`** (force_allocate only) — mints 1 SP into the `used` bucket, bumping max. Required so subsequent voluntary deallocation can refund into current without overflowing max and silently clamping away the SP. See `.claude/rules/stats-system.md` for the four-bucket SP model.

These four are exposed as the **`force_allocate(entity, node)`** primitive. It's the gating-free atom; everything else composes it. **Exception**: `allocate()` (the gated path) inlines steps 1–3 and substitutes `spend(1)` for step 4 — `spend` transfers current → used rather than minting, since the player paid for the allocation.

## The gated path: `allocate(node, entity)`

`allocate()` adds gameplay gates on top of `force_allocate`:

| Guard | Where | Condition |
|---|---|---|
| Target empty, or a refill | `can_allocate` | `node.owned_by == null`, **or** `owned_by == entity` and `allocation_level < stake_level` (a refill needs no adjacency) |
| Has SP | `can_allocate` | `entity.stat_board.skill_points.available() >= 1` |
| Adjacency | `can_allocate` | Target is adjacent to a node already owned by entity, **unless** entity owns nothing yet (the "first allocation is free of adjacency" core-placement rule) |
| Your turn | (caller) | The entity must hold the current turn — `turn_manager.current_entity == entity`. There are no turn phases; `PlayerInputController` (`systems/player_input_controller.gd`) routes the **allocate input channel** here: a bare left-click on an unowned node (`_on_skill_node_left_clicked`). |

The sibling gated verbs follow the same `can_*` / verb shape: `can_stake` / `stake`, `can_extract` / `extract`, `can_move_core` / `move_core`, and `can_deallocate_set` / `deallocate_set` (a set that must stay connected). Read their `can_*` for the guards.

On success: `skill_points.spend(1)` runs (transfers current → used), then steps 1–3 of the side-effects, then `allocated.emit(node, entity)`. Note: `allocate()` does **not** call `force_allocate()` — that would double-bump `used` (once via spend, once via claim). The side-effects are inlined.

## The gated path: `deallocate(node, entity)`

| Guard | Condition |
|---|---|
| Node is owned by entity | `node.owned_by == entity` |
| Node is not the core | `not node.is_core()` |
| Has DP | `entity.stat_board.deallocation_points.current >= 1` |
| No islanding | `entity.navigator.would_disconnect_from(node, entity.core_location)` returns false |
| Your turn (caller) | The entity must hold the current turn (`turn_manager.current_entity == entity`). No turn phases; `PlayerInputController` routes the **deallocate input channel** here: the `D` key pressed while hovering an owned non-core node (`_unhandled_input`). |

On success: removes modifiers, mirror-removes from navigator, clears `owned_by`, then `deallocation_points.deplete(1)` + `skill_points.refund(1)`. Refund lands in `skill_points.current` (voluntary path).

## Forced deallocation: one driver, `EntityCombat.apply_cascade`

**The SP↔wound rule.** To allocate N nodes an entity spends N skill points. When those nodes are force-deallocated (depleted by damage, or islanded by the cascade), the invested SP is **not** refunded as spendable SP: the owner gains **N wounds** instead (1:1 per allocation level). A wound is a reservation block on the SP pool that heals back to spendable SP at `wound_heal_per_turn`. Losing 3 nodes = 3 wounds, plus 3 × `dealloc_damage` off `health` (bypassing mitigation).

**One driver for every forced removal, both worlds.** `EntityCombat.apply_cascade(nodes, alloc, charge)` is the only loop that strips a set of nodes:

- the battle cascade (`BattleSystem._on_node_depleted` live, `cascade_from` on a shadow) — `charge = true`;
- entity death — `deallocate_all_owned` live, `simulate_entity_death` on a shadow — `charge = false`: a corpse's limbs fall off without further wounds or chip. The set is every owned node, **core last**.

Per node, the order is fixed: **snapshot the entry → wound → strip → chip.**

- **Wound before strip.** `SkillPointStat.wound(n)` clamps to `used` (`max − current − wounded − staked`), and stripping a node whose modifier touches `skill_points` max shrinks `used` first — the wound would silently vanish. `wound` `push_warning`s when `n > used` as a tripwire.
- **Chip after strip.** A chip that crosses `health` 0 kills synchronously → `deallocate_all_owned` → a nested `apply_cascade` strips the rest. The outer loop's per-node `n.owner() != self` re-check skips what the nested call took — that guard is written for strip-then-chip.

`force_deallocate(node)` is the live **strip primitive** `apply_cascade` calls: it skips every guard above (no DP cost, no would-disconnect check, no core-protection), releases statuses (a cascade has already released and noted them for the spill — see `status-effects.md`), revokes the node's grants, nulls `owned_by`, dispatches `_on_node_deallocated`, and emits `force_deallocated`. It neither refunds nor wounds — the driver does that. Returns the previous owner.

## Forced fill: `force_fill(node, level)`

The allocate-path primitive for filling an owned node **beyond 1** without minting SP (#915). Precondition: `node.owned_by != null` and `allocation_level <= level <= stake_level`; lowering is not supported (push_error, no-op). Walks `allocation_level` up **one step at a time** through the same `+= 1` write `allocate()`'s refill branch uses, so the local-scale mutator (#376) only ever sees adjacent `(al, al+1)` jumps and `addon_slots` follows. Like a refill it re-grants nothing and emits no `allocated` — the 0→1 transition already did. Never calls `skill_points.claim()`: the fill is free, so the owner's SP pool does not grow. Its consumer is `EntityFactory.spawn_blocker` (a procgen pre-stake, #916), whose nodes only ever leave by `force_deallocate` (no refund) — a `deallocate()` of a force-filled node would refund SP that was never minted.

## When to use which

| Caller | Method | Why |
|---|---|---|
| Player left-clicks an unowned adjacent node | `allocate` | Full gating; SP cost; signals |
| Player presses `D` over an owned non-core node | `deallocate` | Full gating; DP cost; islanding check |
| Forced by attack / death | `EntityCombat.apply_cascade` (strips via `force_deallocate`) | Bypass gates; wound before strip; death uncharged |
| Procgen setup | `force_allocate` (via `GameRoot.spawn_entity(name, color, core)`) | Bypass SP/adjacency; just plant the core |
| Procgen expansion | `force_allocate` directly | Random-walk expansion in dev sandboxes |
| Procgen pre-stake (blockers) | `force_allocate` then `force_fill(node, stake_level)` | Fill 3/3 at spawn; no SP minted for the fill |
| Tests / scripted dev | `force_allocate` | Predictable setup, no resource bookkeeping |

**Never call `force_allocate` from gameplay code.** It mints free SP — using it for a player action quietly breaks the resource loop.

## Scene-authored ownership

Hand-authored levels (e.g. `dev_sandbox.tscn`) set `owned_by` directly in the scene tree, bypassing both `allocate` and `force_allocate`. `AllocationSystem.register_scene_authored_ownership()` walks the graph at `GameRoot._ready` (before `_setup_level`) and calls `claim(1)` per pre-owned node, so the entity's `used` bucket matches the node count. Procgen runs *after* this walk and registers via `force_allocate` directly — no double-counting.

## Optional dependencies

`graph` and `navigator` exports are optional. Without `graph`, adjacency is skipped (any unowned node can be allocated). Without `entity.navigator`, mirror updates and islanding checks are skipped. SP / DP gating still runs. This keeps headless tests working without standing up a full level.

## Signals

- `allocated(node, entity, forced)` — fires from both `allocate` (`forced = false`) and `force_allocate` (`forced = true`)
- `deallocated(node, previous_owner)` — fires only from `deallocate` (the voluntary path)
- `force_deallocated(node, previous_owner)` — fires only from `force_deallocate`

Listeners that care about voluntary vs. forced can branch on `allocated`'s `forced` flag, or on which of the two deallocation signals fired; wound vs refund is decided by the caller — `EntityCombat.apply_cascade` wounds, voluntary `deallocate` refunds.
