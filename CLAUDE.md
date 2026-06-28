# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Skill Tree of Life** — a Godot 4.4 game where the skill tree *is* the game. Entities (players, NPCs) live on a graph of skill nodes, allocating nodes to expand territory and stats. Turn-based, initiative-driven. See `docs/GDD.md` for the full pitch and `docs/design/index.md` for design doc reading order.

## Running the Game

```
godot --editor .                          # open project in editor
godot --path . scenes/dev_sandbox.tscn    # hand-authored sandbox (player + small graph)
godot --path . scenes/procgen_play_sandbox.tscn   # procgen level + player + AI starters
```

No build step, test runner, or lint tool. Each level scene extends `scenes/game_root.tscn` (the composition root); subclasses populate content via the `_setup_level()` hook.

## Architecture

`GameRoot` (`scenes/game_root.gd`) — per-level composition root; mounts VFX, wires systems, calls `_setup_level()`, then `UIRoot.compose(self)`. Subclass + override `_setup_level()` to author or generate level content. Spawn entities via `spawn_entity(name, color, core_location, core_class)`.
`Graph` (`graph/graph.gd`) — owns `SkillNode`s + `Edge`s + `entities_container`; pure topology, structural signals.
`Entity` (`entity/entity.gd`) — players and NPCs use the same class; ownership is set by `AllocationSystem`. Composes a `CoreClass` (`entity/core/`) that brands the entity with identity modifiers + an `on_turn_started` hook; `BalancedCore` is the +10 STR/DEX/INT baseline.
`Navigator` (`graph/navigator.gd`) — full-graph `AStar2D` mirror; `EntityNavigator` (`entity/entity_navigator.gd`) is the per-entity subgraph mirror used for cut-vertex / islanding queries.
`TurnManager` (`systems/turn_manager.gd`) — initiative ticks to 100 → entity acts (single implicit phase — intent is by input channel, not phase gates); `end_turn()` deducts 100. See `.claude/rules/turn-manager.md`.
`AllocationSystem` (`systems/allocation_system.gd`) — `allocate` / `deallocate` (gated) + `force_allocate` / `force_deallocate` (primitives). See `docs/domain/allocation_system.md`.
`BattleSystem` (`systems/battle_system.gd`) — owns active `AttackPlan`, runs `launch_attack` (resolve → VFX await → AP deduction), drives forced-dealloc cascade. See `docs/domain/attack_plan_system.md`.
`VisionSystem` (`systems/vision_system.gd`) — fog of war; reads owned subgraph + per-entity `vision_range` / `sensor_range`. See `docs/domain/vision-system.md`.
`LootSystem` (`systems/loot_system.gd`) — killing-blow rewards: XP to the killer (#68) + a `SkillDustAddon` relic on the victim's former core (#69). Resolves the killer from its injected `turn_manager`; reacts to the pre-cleanup `Events.entity_dying` phase (corpse still owns its nodes) so it snapshots before AllocationSystem's `entity_died` strip. See `docs/domain/loot-system.md`.
`StatBoard` (`stats_system/`) — PoE-style modifier pipeline. See `.claude/rules/stats-system.md` for IDs, pipeline, gotchas — **update it when the stat system changes.**
`GraphProcgen` (`procgen/graph_procgen.gd`) — static pipeline; `generate(config, graph)` returns nodes + starting_nodes. See `docs/domain/procgen.md` (topology) and `docs/domain/procgen-v3.md` (content: StatPack + phased draw).

Spawning runtime entities: subclass `GameRoot`, override `_setup_level()`, call `spawn_entity(name, color, core_location, core_class)` — it duplicates the default stat board, parents under `graph.entities_container`, force-allocates the core node, and assigns the class. See `scenes/procgen_play_sandbox.gd`.

## Autoloads (registered in `project.godot`)

| Singleton | Purpose |
|---|---|
| `SceneTransition` | Fade in/out + loading progress bar |
| `SceneLoader` | Async scene loading |
| `Events` | Global signal bus (`skill_node_depleted`, etc.) |
| `StatRegistry` | StatDef lookup by id |
| `DebugClipboard` | Press `c` while hovering a SkillNode to copy its full state (archetype, owner, hp, modifiers, addons) to the system clipboard |

## Design docs

Entry points: `docs/GDD.md` (master GDD) · `docs/design/index.md` (full index with reading order).

## Issue tracking

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`). Labels: `core`, `design`, plus defaults.

## Godot conventions

- `@tool` on `SkillNode`, `Entity`, `Graph` — they run in the editor.
- `%NodeName` (unique name) for child node access in scenes; UIRoot reads systems via `%PlayerInputController`, `%VisionSystem`, etc.
- `call_deferred` / `await` for post-ready init.

## Knowledge accumulation

When you learn something non-obvious — a gotcha, a hidden constraint, a workflow surprise — **proactively offer to write it down**.

- **Rule files** live in `.claude/rules/<module>.md`. If you hit a gotcha while working on a module, check if a rule file exists; create or update it. Keep rules current — a stale rule is worse than no rule.
- **Small gotchas (<200 tokens):** inline in the relevant rule file. Lead with the rule, then **Why:** / **How to apply:**.
- **Larger context** (multi-paragraph, decision trees, code samples): `docs/domain/<topic>.md` (engineering knowledge, distinct from `docs/design/` which is game design).
- Game-design knowledge belongs in `docs/design/` or as a GitHub Issue (`design` label) — not inline here.
