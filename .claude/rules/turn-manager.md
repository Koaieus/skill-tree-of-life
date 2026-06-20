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

`TurnManager` joins the `"turn_manager"` group (constant `TurnManager.GROUP`) in `_enter_tree`. `Entity._find_turn_manager()` uses `get_tree().get_first_node_in_group(...)`. A tree-walk via `get_children()` missed it — TM lives at `Graph/Systems/TurnManager`, never a direct child of an Entity ancestor. Single instance per level.

## Wiring a new level

After `_setup_level()` resolves the player, GameRoot kicks the first turn:
```gdscript
player.initiative_current = 100.0
turn_manager.start_turn(player)
```
The first call is what skips the initial tick race. Entities are in group `entities` via `Entity._enter_tree()` — no manual registration.

## Turn-start upkeep

`Entity._on_turn_started` (subscribed to `turn_started`) refills `action_points` / `deallocation_points`, replenishes `xp` by `xp_per_turn`, heals `wound_heal_per_turn` wounded SP, and calls `refill()` on each owned `SkillNode` (combat HP back to max). See `.claude/rules/stats-system.md` for the full list.
