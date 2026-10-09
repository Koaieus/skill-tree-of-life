# Node HP

Per-node combat HP is a `PoolStat` (id `node_health`, def `node_combat_health`)
on `SkillNode.node_board` — see `docs/domain/stats-system.md` → "Pool
stats" → "Node combat health" for the board-level mechanics. This document
covers the parts that live outside the stat pipeline: `regen_stacks` and how
turn-start regen (D-9) and the CoreClass aura (D-10) apply on top of it.

## Current shape

The logic lives in `NodeCombat` (`combat/node_combat.gd`); `SkillNode` delegates
and keeps the notification halves (`notify_damaged`, `notify_healed`) that emit
its signals and `Events`.

- `get_max_hp()` / `get_current_hp()` — reads of the `node_health` PoolStat's
  `.value` / `.current` (`NodeCombat.get_max_hp` / `get_current_hp`).
- `refill()` (`NodeCombat.refill`) — restores the pool to full. Fires **only** on
  allocation (`_refresh_hp_binding`, silent); the turn-start regen does not call it.
- `NodeCombat.take_damage(amount, source)` — rounds the amount up once at entry
  (ADR 0033), applies `Mitigation.apply`, soaks against the pool, routes
  overflow to `owned_by.stat_board.health` iff this is a core node, notifies
  `damaged` + `Events.skill_node_damaged`, and `depleted` +
  `Events.skill_node_depleted` on zero. Sets `_damaged_since_upkeep = true`
  whenever a hit actually reduces HP — this gates the next turn's regen.
- `NodeCombat.heal_damage(amount, source)` — restores HP, clamped at max, notifies
  `healed` + `Events.skill_node_healed`.

## Turn-start regen (D-9) — replaces refill-to-full

`Entity.begin_turn` does not refill owned nodes to full (owner, 2026-09-30): node-local
stat boards and readouts make a node's damage state legible on the node itself,
so it needs no wiping every round. Instead, per owned node,
`SkillNode.apply_turn_regen()` runs:

- took damage since the last upkeep → `regen_stacks = 0`, no base heal;
- else if HP < max → heal `node_healing + regen_stacks × node_healing_ramp`,
  then `regen_stacks += 1`;
- else (already at max) → `regen_stacks = 0`.

`node_healing` and `node_healing_ramp` are ordinary node-local stats (same
mechanism as `range` — see `docs/domain/stats-system.md` → "Local stats"),
read via `get_local_value`. There is deliberately **no cap stat**: the ramp
self-limits because it stops the moment the node reaches max HP and resets.

### `regen_stacks` is runtime state, not a stat

`SkillNode.regen_stacks: int` — per-node ephemeral game state (how many consecutive
undamaged turns this node has regenerated), not something the modifier
pipeline needs to derive or that other systems scale. It resets to 0 on
damage and on reaching full HP, and increments by exactly 1 each turn
`apply_turn_regen` grants a ramped heal. A future `CoreClass` that wants to
zero the ramp (D-9's named differentiation lever) reads/writes
`node_healing_ramp = 0` on the stat, not this field — `regen_stacks` just
counts how many times the ramp has paid out.

### The dealloc/realloc refill is accepted, not a bug

`refill()` still runs on allocation (`_refresh_hp_binding`), so a low-HP node
can be deallocated and reallocated to come back full. This is a **known,
accepted interaction** (D-9): it costs 1 DP (+2 MP if the core sits on that
node) and requires topology that permits the dealloc without islanding — a
real turn-budget price. Do not "fix" this without a design decision first;
see D-9 in `docs/adr/legacy-mvp-decisions.md`.

## The CoreClass healing aura (D-10)

A `CoreClass` may carry a `HealAuraEffect` (`effects/heal_aura_effect.gd`) —
an `AuraEffect` subclass authored on `CoreClass.effects` like any other class
effect, radiating from the entity's `core_location` (there is no separate
`CoreClass.aura` field, and no standalone `CoreAura`/`HealAura` pair).
`Entity.begin_turn` dispatches
`_on_turn_start`, where `HealAuraEffect` walks the **owned** subgraph via the
shared `AuraEffect._distances` (`reach`/`metric`, never `graph.navigator` —
see `.claude/rules/graph.md` "Reach queries") and calls `node.heal_damage`
for every node it reaches.

This runs **outside** `apply_turn_regen`'s gate: the aura heals through
combat (applies even to a node that took damage this turn) and grants no
ramp (never touches `regen_stacks`). `base` and `con_coefficient`
(`v = base + con_coefficient × sqrt(CON)`, CON read live off the board every
turn) are authored directly on the `HealAuraEffect` resource, not board
stats — see D-10 in `docs/adr/legacy-mvp-decisions.md` for the rationale (why
flat-not-percent, why the aura doesn't need to bribe the core forward). Its
`Shape`/`Scaling` prose may not match the code; the `HealAuraEffect` source is
authoritative.

## Why a pool, not a bare field

Node HP is the `node_combat_health` `PoolStat` on `node_board`, so addons and
keystones modify it through the ordinary pipeline. The
`get_max_hp()` / `get_current_hp()` boundary is the seam: a change to how the cap
or current are derived stays confined to those two methods (plus
`_refresh_hp_binding`) without rippling into `take_damage` / `heal_damage` /
`apply_turn_regen` callers.


## Test entities without stat boards

`take_damage` early-returns when `owned_by == null` and tolerates
`owned_by.stat_board == null` (max → 0, no overflow routing). Cascade dealloc
in `BattleSystem._on_node_depleted` skips the wound + core-HP-loss steps if
the defender has no board. So a test entity with no board still participates
in the highlight / plan flow; it just can't take meaningful damage, and
`apply_turn_regen` no-ops (no `node_health` pool to read).
