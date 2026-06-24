---
description: Turn manager quick-reference — phase order, initiative, turn-start hooks
---

# Turn manager

`systems/turn_manager.gd` owns who has the turn (`current_entity`), what phase they're in (`current_phase`), and the initiative clock that hands turns over.

## Phase order

`CONTRACT → EXPAND → BATTLE → end_turn` (per entity, per turn). `advance_phase()` walks one step; from `BATTLE` it returns false so the caller calls `end_turn()`.

| Phase | What's allowed | Stat consumed |
|---|---|---|
| `CONTRACT` | Voluntary deallocation only | `deallocation_points` |
| `EXPAND`   | Allocation only | `skill_points` |
| `BATTLE`   | Attacks (melee / ranged / magic) | `action_points` |

Gates: `can_allocate()` returns true iff `current_phase == EXPAND`; `can_deallocate()` iff `CONTRACT`; `can_act()` iff `BATTLE`. The split prevents misclicks burning a dealloc point when the player meant to allocate (and vice versa).

## Initiative

`tick()` advances every node in group `entities` by its `initiative_speed.value`. `end_turn()` deducts 100 from the previous entity, then `_tick_until_ready()` ticks until at least one entity ≥ 100 and starts the highest's turn. `start_turn()` resets phase to `CONTRACT` and emits `turn_started` + `phase_changed`.

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
a default controller to any entity that doesn't have one:
`PlayerController` for `self.player`, `AIController` for everyone else.
That's the catch-all that keeps hand-authored sandbox scenes
(`dev_sandbox.tscn`, `first_level_sandbox.tscn`) playable without each
remembering to wire controllers manually. Explicit scene composition
wins — `_ensure_controllers()` skips entities that already have a child
`EntityController`.

## Turn-start upkeep

`Entity._on_turn_started` (subscribed to `turn_started`) refills `action_points` / `deallocation_points`, replenishes `xp` by `xp_per_turn`, heals `wound_heal_per_turn` wounded SP, and calls `refill()` on each owned `SkillNode` (combat HP back to max). See `.claude/rules/stats-system.md` for the full list.
