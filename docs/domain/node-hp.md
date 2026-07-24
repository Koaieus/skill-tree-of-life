# Node HP

Per-node combat HP is a `PoolStat` (id `node_health`, def `node_combat_health`)
on `SkillNode.node_board` — see `.claude/rules/stats-system.md` → "Local
stats" → "Node combat health" for the board-level mechanics. This document
covers the parts that live outside the stat pipeline: `regen_stacks` and how
turn-start regen (D-9) and the CoreClass aura (D-10) apply on top of it.

## Current shape

- `SkillNode.get_max_hp()` / `get_current_hp()` — thin reads of the
  `node_health` PoolStat's `.value` / `.current`.
- `SkillNode.refill()` — restores the pool to full. Fires **only** on
  allocation (`_refresh_hp_binding`, silent) now — see "Turn-start regen"
  below for why the turn-start call was removed.
- `SkillNode.take_damage(amount, source)` — applies `Mitigation.apply`, soaks
  against the pool, routes overflow to `owned_by.stat_board.health` iff this
  is a core node, emits `damaged` + `Events.skill_node_damaged`, emits
  `depleted` + `Events.skill_node_depleted` on zero. Also sets
  `_damaged_since_upkeep = true` whenever a hit actually reduces HP (soaked
  > 0) — this is what gates the next turn's regen.
- `SkillNode.heal_damage(amount, source)` — restores HP, clamped at max,
  emits `healed` + `Events.skill_node_healed`.

## Turn-start regen (D-9) — replaces refill-to-full

`Entity._on_turn_started` no longer refills owned nodes to full. Instead,
per owned node, `SkillNode.apply_turn_regen()` runs:

- took damage since the last upkeep → `regen_stacks = 0`, no base heal;
- else if HP < max → heal `node_healing + regen_stacks × node_healing_ramp`,
  then `regen_stacks += 1`;
- else (already at max) → `regen_stacks = 0`.

`node_healing` and `node_healing_ramp` are ordinary node-local stats (same
mechanism as `range` — see `.claude/rules/stats-system.md` → "Local stats"),
read via `get_local_value`. There is deliberately **no cap stat**: the ramp
self-limits because it stops the moment the node reaches max HP and resets.

### `regen_stacks` is runtime state, not a stat

`SkillNode.regen_stacks: int` — same reasoning as node HP's own promotion
history below: it's per-node ephemeral game state (how many consecutive
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
see D-9 in `docs/design/mvp_decisions.md`.

## The CoreClass healing aura (D-10)

A `CoreClass` may carry a `CoreAura` (`effects/core_aura.gd`) — e.g.
`HealAura` (`effects/heal_aura.gd`) — radiating from the entity's
`core_location`. `Entity._on_turn_started` computes
`aura.values_from(core_location, navigator)` once per turn (one BFS over the
**owned** subgraph via `HopRangeFinder.gather`, never `graph.navigator` — see
`.claude/rules/graph.md` "Reach queries"), then calls `aura.apply(node,
value)` for every node the aura reaches.

This runs **outside** `apply_turn_regen`'s gate: the aura heals through
combat (applies even to a node that took damage this turn) and grants no
ramp (never touches `regen_stacks`). `base` and `range` are authored
directly on the `CoreAura` resource, not board stats — see D-10 in
`docs/design/mvp_decisions.md` for the full rationale (why two independent
knobs, why flat-not-percent, why the aura doesn't need to bribe the core
forward).

## Promotion history (why the pool, not a bare field)

Node HP used to be a plain `current_hp: float` field with no modifier
pipeline underneath it, for a `DerivedStatModifier`-era reason that no longer
applies (see git history around #149/#171 for the original writeup). It was
promoted to the `node_combat_health` `PoolStat` on `node_board` once
node-local stats existed as infrastructure (addons, keystones). The
`get_max_hp()` / `get_current_hp()` boundary is still the seam: any future
change to how the cap or current are derived should stay confined to those
two methods (plus `_refresh_hp_binding`) without rippling into `take_damage`
/ `heal_damage` / `apply_turn_regen` callers.

## Test entities without stat boards

`take_damage` early-returns when `owned_by == null` and tolerates
`owned_by.stat_board == null` (max → 0, no overflow routing). Cascade dealloc
in `BattleSystem._on_node_depleted` skips the wound + core-HP-loss steps if
the defender has no board. So a test entity with no board still participates
in the highlight / plan flow; it just can't take meaningful damage, and
`apply_turn_regen` no-ops (no `node_health` pool to read).
