# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Skill Tree of Life** — a Godot 4.4 game where the skill tree *is* the game. Entities (players, NPCs) live on a graph of skill nodes, allocating nodes to expand their territory and improve their stats. The game has turn-based mechanics with initiative-based ordering and a rock-paper-scissors combat system (R/G/B node types).

## Running the Game

Open and run from the Godot editor:
```
godot --editor .          # open project in editor
godot --path . scenes/game_root.tscn   # run directly (headless-friendly)
```

There is no build step, test runner, or lint tool. The game loads directly into `dev_level_tree_graph.tscn` via `autoload/game.gd`.

## Architecture

### Core game loop

`Game` (autoload singleton, `autoload/game.gd`) bootstraps the game:
1. Loads `scenes/game_root.tscn` as the persistent scene container.
2. Async-loads the level (`levels/dev_level_tree_graph.tscn`) under `GameRoot/LevelLayer`.
3. Wires up `Game.tree_graph`, `Game.navigator`, `Game.turn_manager`, and `Game.player`.

### TreeGraph (`graph/tree_graph.gd`)
Extends Godot's `GraphEdit`. The skill tree UI *is* the game world. `TreeNode` (extends `GraphNode`) are the skill nodes; connecting/disconnecting them fires signals that update the `Navigator`'s A* graph.

### TreeEntity / Player (`tree_entity.gd`, `player.gd`)
`TreeEntity` is a `Node` that lives as a child of a `TreeNode` — its "core" node. It owns nodes by calling `tree_node.allocate_to(self)`, which attaches its `StatModifier` list to the entity's stat board. `Player extends TreeEntity` and checks `skill_points` before allocating.

### Navigator (`graph/navigator.gd`)
Maintains an `AStarSkillTree` (custom `AStar2D`) in sync with the `TreeGraph`. Each `TreeNode` gets an integer vertex ID managed here. Path queries go through `navigator.astar`.

### TurnManager (`systems/turn_manager.gd`)
Initiative-based turn order. Each game tick (`ticked` signal), entities progress their initiative; once it reaches 100 they enter the `initiative-ready` group and get a turn. `end_turn()` deducts 100 initiative and cycles.

### Stat system (`stat_system/`)
**Current state (v1):** Stats are subclassed from `Stat extends Resource`. Each concrete stat (e.g. `HealthPoolStat`, `InitiativeStat`) is a GDScript class. The `key` is the GDScript object itself — used as a dict key in `Stats.map`. `StatsManager` (node component) wraps a `Stats` resource and provides `add_stat_modifier` / `remove_stat_modifier`.

**Planned direction (v2):** See `docs/design/stat_system.md`. The direction is `StatDefinition` resources with `StringName` IDs (replacing GDScript-as-key), `RuntimeStat` objects created at runtime, and a `StatRegistry` autoload replacing the fragile `StatMetaDataRepository`. This is an active refactor — prefer the v2 patterns when adding new stats.

Hierarchy:
- `stat_system/stat.gd` — base `Stat` resource
- `stat_system/computed/` — scalar stats with modifier pipeline (`_computed_stat.gd`, `int_stat.gd`, `float_stat.gd`)
- `stat_system/aggregated/pool/` — pool stats with current/max (`_pool_stat.gd`, growable variant)
- `stat_system/modifier/` — `StatModifier` resources applied to stats
- `stats/` — concrete `EntityStats extends Stats` board with all gameplay stats exported
- `stats/list/` — concrete stat implementations (`ExpStat`, `InitiativeStat`, `HealthPoolStat`, etc.)

### UI (`ui/`)
- `ui/stats_panel/` — entity stats display, driven by `StatsManager`
- `ui/widgets/bar_widget.gd` — reusable bar display
- `ui/progress_bar_decorated.gd` — decorated progress bar
- `ui/tooltip.gd` — hover tooltip for skill nodes

### VFX (`vfx/edge_beam.gd`)
Beam effect along graph edges when a node is allocated.

## Autoloads (registered in `project.godot`)

| Singleton | Purpose |
|---|---|
| `Game` | Global game state, turn wiring, level loading |
| `SceneTransition` | Fade in/out + loading progress bar |
| `SceneLoader` | Async scene loading |
| `StatUIConfig` | Maps stat keys to UI display config |
| `StatMetaDataRepository` | Stat name/description lookup (fragile, slated for removal in v2) |
| `Skills` | Global skill definitions |
| `XRM` | Global transform utilities |
| `DeferOnce` | Deferred single-fire utility |

## Key design docs (`docs/design/`)

- `stat_system.md` — definitive v2 stat architecture, canonical stat vocabulary, modifier operators
- `core_classes.md` — all entity core classes (Allround, Predator, Bulwark, Ninja, Hive, Halo, Serpent) with mechanics
- `combat_system.md` — R/G/B node type triangle, per-node health, attack resolution
- `metagame.md` — progression, run structure
- `lore.md` — narrative context

## Godot conventions used here

- `@tool` is used on `TreeNode`, `TreeEntity`, and `Player` so they run in the editor.
- `%NodeName` (unique name) shorthand is used for child node access in several scenes.
- `call_deferred` / `await` patterns are common for post-ready initialization (e.g. `Game.game_ready` signal).
- Stat keys are currently `GDScript` objects (`get_script()`) — do not rename or move stat files without updating all `StatModifier.stat_key` references.
