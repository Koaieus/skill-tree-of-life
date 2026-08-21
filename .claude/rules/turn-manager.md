---
description: Turn manager quick-reference — single-phase turn, initiative, turn-start hooks
paths:
  - "systems/turn_manager.gd"
  - "entity/controller/**"
  - "scenes/game_root.gd"
---

# Turn manager

`systems/turn_manager.gd` owns who has the turn (`current_entity`) and the initiative clock that hands turns over.

## Single-phase turn (no more CONTRACT/EXPAND/BATTLE)

There is **one implicit phase per turn** (issue #60 removed the 3-phase model). On `turn_started` every per-turn budget replenishes; the entity spends them in any order until End Turn. There is no `Phase` enum, no `current_phase`, no `advance_phase()`, no `phase_changed` signal, and no `can_allocate`/`can_deallocate`/`can_act` on the TurnManager.

Intent is disambiguated **by input channel**, each gated only by "is it your turn?" + its own budget (all enforced inside the systems, not the TurnManager):

| Intent | Channel | Budget |
|---|---|---|
| Allocate | bare left-click on an unowned node | `skill_points` + adjacency (`AllocationSystem.allocate`) |
| Deallocate | hover a node + press `D` | `deallocation_points`, non-islanding (`AllocationSystem.deallocate`) |
| Move core | left-click own core, then click an adjacent owned node (#21) | `movement_points` (`AllocationSystem.move_core`) |
| Attack / cast | `AttackModeBar` picks the mode, then node clicks feed the plan | `action_points` (`BattleSystem`) |

Click dispatch lives in `PlayerInputController._on_skill_node_left_clicked` (battle plan → core-move → allocate) and `_unhandled_input` (the `D` deallocate channel). `can_player_act()` = your turn + AP > 0.

> The polished AoE2-style contextual **Action Bar** (issue #60 Q2/A2: out-of-viewport square action icons with shortcut labels) is **deferred to a follow-up** — for now the `AttackModeBar` + `D`-hotkey + click-core-to-move cover the channels.

## Initiative

Initiative is the **`initiative` PoolStat** on each entity's stat board (a `CyclicPoolStatDef` — see `.claude/rules/stats-system.md`). The cap is that entity's action threshold (default 100, tweakable per entity via modifiers); `current` is the clock.

`tick()` replenishes every entity's `initiative` pool by its `initiative_speed.value`. When a pool crosses its cap it fires `replenished` (the entity handles this by joining `Entity.READY_GROUP` / `&"ready_to_act"`) and the cyclic def carries the overshoot into the next cycle — so **`end_turn()` deducts nothing**; the deduction already happened at the crossing. `_tick_until_ready()` ticks until `READY_GROUP` is non-empty, then serves the member with the highest carried `current` (more overshoot wins), deprioritising the just-acted entity on ties. `start_turn()` removes the entity from `READY_GROUP`, sets `current_entity`, and emits `turn_started`.

Readiness is **group membership, not `current >= cap`** — because the carry-reset drops `current` back near zero the instant the clock crosses. The `_tick_until_ready` loop is synchronous (no per-tick frame yield); the InitiativeBar animates the climb on its own via a tween bound to the pool's `current_changed`, and holds "full" off `replenished` until `turn_started` drains it.

## Discovery

`TurnManager` joins the `"turn_manager"` group (constant `TurnManager.GROUP`) in `_enter_tree`. `Entity._find_turn_manager()` uses `get_tree().get_first_node_in_group(...)`. A tree-walk via `get_children()` missed it — TM lives at `GameRoot/Systems/TurnManager` (sibling of Graph), never a direct child of an Entity ancestor. Single instance per level.

## Wiring a new level

After `_setup_level()` resolves the player, GameRoot kicks the first turn:
```gdscript
player.initiative_current = 100.0
turn_manager.start_turn(player)
```
The first call is what skips the initial tick race. Entities are in group `entities` via `Entity._enter_tree()` — no manual registration.

## Every Entity needs an EntityController

`TurnManager.start_turn(entity)` hands the turn over but does not decide
what the entity *does*. Action comes from the entity's `EntityController`
child (`AIController` for NPCs, `PlayerController` for the human — a no-op
subclass that exists so the UI's End Turn button is the legal turn-ender).
An entity without a controller child receives `turn_started` and then
sits there forever; the loop stalls.

`GameRoot._ensure_controllers()` runs after `_setup_level()` and attaches
a default controller to any entity that doesn't have one: `PlayerController`
where `Entity.is_human_controlled` is set, `AIController` otherwise (#475 —
this reads the per-entity flag, not entity identity against `self.player`,
so it scales past a single human). That's the catch-all that keeps
hand-authored sandbox scenes (`dev_sandbox.tscn`, `first_level_sandbox.tscn`)
playable without each remembering to wire controllers manually. Explicit
scene composition wins — `_ensure_controllers()` skips entities that already
have a child `EntityController`. `GameRoot.apply_roster()` is the
roster-driven way to set `is_human_controlled` + `faction` together from a
`ParticipantRoster`; a hand-authored scene sets `is_human_controlled` (and
`faction`) directly on the node instead.

## Turn-start upkeep

`Entity._on_turn_started` (subscribed to `turn_started`) refills `action_points` / `deallocation_points`, replenishes `xp` by `xp_per_turn`, heals `wound_heal_per_turn` wounded SP, and calls `refill()` on each owned `SkillNode` (combat HP back to max). See `.claude/rules/stats-system.md` for the full list.

## Testing an EntityController in isolation (#378)

Building a fixture with `TurnManager.new()` + `Entity.new()` + a controller
child (no `game_root.tscn`) hits three gotchas together:

- **`Entity._ready()` duplicates `stat_board` again** (`stat_board =
  stat_board.duplicate(true)`, on top of whatever the fixture already
  duplicated). Configure stat values (`set_current`, etc.) *after* the entity
  is `add_child`ed, not before — a pre-`_ready` write lands on the object
  `_ready` then discards, silently.
- **First turn can mint extra SP.** `apply_per_turn_upkeep()` replenishes `xp`
  by `xp_per_turn`; if the board's intrinsic-scaled value already crosses the
  level-up threshold from 0, `Entity._on_xp_replenished` grants SP via
  `skill_points.grant()` before the controller's `take_turn` even runs. Don't
  assert an exact post-turn SP count against a fixture entity's very first
  turn — assert the *behavior* that doesn't depend on the economy (e.g.
  "every reachable frontier node got allocated"), or the number will drift
  for reasons that have nothing to do with what you're testing.
- **Add the controller child AFTER the entity enters the tree**, mirroring
  `GameRoot._ensure_controllers()` (which runs post-`_setup_level`). This
  makes `Entity`'s own `turn_started` connection (upkeep) register before the
  controller's, so upkeep runs before `take_turn` on the very first turn —
  reversed, the two race inside the same synchronous `emit()` and, with
  `turn_delay = 0`, a single-entity fixture can recurse `take_turn` straight
  into a stack overflow (`TurnManager._tick_until_ready` re-selecting the
  same entity with nothing else to hand the turn to). Give the fixture a
  second, idle entity (e.g. `PlayerController`, whose `take_turn` is a no-op)
  so the clock has somewhere to park after the AI's turn ends.
- **`AIController` mutates only through a `CommandApplier` (#512), which it
  resolves by walking up to a `GameRoot` ancestor** — absent one it allocates
  nothing AND never ends its turn, so the whole loop stalls. Set
  `command_applier_override` / `battle_system_override` on the controller
  instead of composing a full `game_root.tscn`; unset in production. The
  fixture also needs a `Graph` with both entities under
  `graph.entities_container` — a command names its actor by `entity_id`, minted
  only on entry to that container, and id 0 resolves to nothing.
- **`SkillNode.take_damage(amount, source)` re-runs `amount` through
  `Mitigation.apply` even when you pass a raw float** — armor/floor apply
  twice if you also expect the caller's own mitigation math. To set an exact
  HP in a fixture, pass a `DamageInstance` with `type = TRUE` as `source`
  (`Mitigation.apply` returns `raw.amount` unchanged for `TRUE`); the `amount`
  argument only matters for the `amount <= 0.0` early-out guard.
- **Mana behaves like SP** (same shape as the SP-minting gotcha above):
  turn-start upkeep ADDS `mana_per_turn` before `take_turn` runs, so a
  pre-turn `mana.set_current(0.0)` doesn't stay 0 once the controller reads
  it. To force "can't afford this spell," bump `SpellDef.mana_cost` on a
  `duplicate(true)` of the spell instead of draining the pool.
- **A fixture that exercises `graph.navigator` (the GLOBAL mirror) must build
  nodes/edges via `Graph.add_skill_node` / `Graph.add_edge`, not a raw
  `container.add_child`** — the raw form never emits `node_added`/`edge_added`,
  so the global mirror stays empty (see `.claude/rules/graph.md`). Bit
  `MagicAttackPlan`'s `HopRangeFinder` targeting specifically: it traverses
  `graph.navigator`, not the entity's own owned-subgraph mirror, so a fixture
  that only ever populated the latter (fine for ranged/frontier tests) silently
  produced zero valid magic targets.
