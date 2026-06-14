# Node HP

Per-node combat HP lives as a plain `current_hp: float` field on `SkillNode`,
*not* as a stat in the modifier pipeline. This is a deliberate scaffolding
choice for the ranged-attack proof-of-concept; the document below explains
the reasoning and the seam for promoting it later.

## Current shape

- `SkillNode.current_hp: float` — ephemeral game state.
- `SkillNode.get_max_hp() -> float` — reads `owned_by.stat_board.get_value(&"node_health")`.
- `SkillNode.refill()` — sets `current_hp = get_max_hp()`. Called on:
  - first allocation (`owner_changed` → not null),
  - turn start of the owning entity (`Entity._on_turn_started`).
- `SkillNode.take_damage(amount, source)` — applies `Mitigation.apply`, soaks
  against `current_hp`, routes overflow to `owned_by.stat_board.health` iff
  this is a core node, emits `damaged` + `Events.skill_node_damaged`, emits
  `depleted` + `Events.skill_node_depleted` on zero.

A `Stat.value_changed` subscription on the bound `node_health` stat clamps
`current_hp` to the new cap if max drops mid-turn.

## Why not in the modifier pipeline yet

`DerivedModifierDef` (`stats_system/derived_modifier_def.gd`) binds to **one
StatBoard** and looks source stats up on that same board
(`board.get_stat(id)` at `derived_modifier_def.gd:37`). `StatFormula.compute`
takes a single board argument.

A faithful "node-local + owner stats → node max HP" derivation would need:

- Either a **second StatBoard on SkillNode** (overkill: would carry the full
  pool/scalar plumbing for one stat),
- Or **cross-board derivation** (a new formula kind that knows about an owner
  board alongside the local board — not a supported pattern today).

And critically: **there are no node-local stats yet**. Building the
infrastructure for state that doesn't exist would be premature.

## Promotion path (when node-local stats arrive)

1. Introduce a minimal per-node board (e.g. `NodeStatBoard`) that holds the
   small handful of stats nodes actually carry — likely `node_health_local`,
   `node_armour_local`, etc.
2. Add a `CrossBoardStatFormula` (or generalise `StatFormula`) that takes an
   owner-board reference via constructor / sidecar lookup.
3. Replace `SkillNode.get_max_hp()` with a `PoolStat`-style max read off
   the local board, whose `node_health` stat carries a derived modifier
   computed from `owner_board.node_health + node_board.node_health_local`.
4. `current_hp` becomes `PoolStat.current` — the bare-field/`refill()` API
   collapses into existing PoolStat machinery (`restore_to_full`, etc.).

The current single-stat lookup at the `get_max_hp` boundary is the seam: any
future change should be confined to that method (and the `_refresh_hp_binding`
subscription) without rippling into `take_damage` or callers.

## Why not `PoolStat` on SkillNode now

`PoolStat` works fine in isolation, but its modifier-pipeline hooks
(`add_modifier`, `_apply_max_change`) implicitly assume the stat lives on
some StatBoard that routes modifier changes through it. Mounting one on
`SkillNode` with no surrounding board is half a system. We'd lose the
`current ≤ cap` invariant on max changes only by piggybacking the existing
`value_changed` signal of the entity board's `node_health` stat — which is
exactly what `_refresh_hp_binding` does, but cleaner as a flat float for
now.

## Test entities without stat boards

`take_damage` early-returns when `owned_by == null` and tolerates
`owned_by.stat_board == null` (max → 0, no overflow routing). Cascade dealloc
in `BattleSystem._on_node_depleted` skips the wound + core-HP-loss steps if
the defender has no board. So a test entity with no board still participates
in the highlight / plan flow; it just can't take meaningful damage.
