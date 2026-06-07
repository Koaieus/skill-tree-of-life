# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Skill Tree of Life** — a Godot 4.4 game where the skill tree *is* the game. Entities (players, NPCs) live on a graph of skill nodes, allocating nodes to expand territory and stats. Turn-based, initiative-driven. See `docs/GDD.md` for the full pitch and `docs/design/index.md` for design doc reading order.

## Running the Game

```
godot --editor .                          # open project in editor
godot --path . scenes/game_root.tscn      # run directly (headless-friendly)
```

No build step, test runner, or lint tool. Game boots into `dev_level_tree_graph.tscn` via `autoload/game.gd`.

## Architecture

`Game` (`autoload/game.gd`) — bootstraps the game; wires `tree_graph`, `navigator`, `turn_manager`, `player`.  
`TreeGraph` (`graph/tree_graph.gd`) — extends `GraphEdit`; the skill tree UI *is* the game world; `TreeNode` extends `GraphNode`.  
`TreeEntity` / `Player` (`tree_entity.gd`, `player.gd`) — entity owns nodes via `tree_node.allocate_to(self)`.  
`Navigator` (`graph/navigator.gd`) — maintains `AStarSkillTree` (custom `AStar2D`) mirroring the live graph.  
`TurnManager` (`systems/turn_manager.gd`) — initiative ticks to 100 → entity acts; `end_turn()` deducts 100.  
`StatBoard` (`stats_system/`) — PoE-style modifier pipeline. See `.claude/rules/stats-system.md` for IDs, pipeline, gotchas — **update it when the stat system changes.**

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

## Design docs

Entry points: `docs/GDD.md` (master GDD) · `docs/design/index.md` (full index with reading order).

## Issue tracking

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`). Labels: `core`, `design`, plus defaults.

## Godot conventions

- `@tool` on `TreeNode`, `TreeEntity`, `Player` — they run in the editor.
- `%NodeName` (unique name) for child node access in scenes.
- `call_deferred` / `await` for post-ready init (e.g. `Game.game_ready` signal).

## Knowledge accumulation

When you learn something non-obvious — a gotcha, a hidden constraint, a workflow surprise — **proactively offer to write it down**.

- **Rule files** live in `.claude/rules/<module>.md`. If you hit a gotcha while working on a module, check if a rule file exists; create or update it. Keep rules current — a stale rule is worse than no rule.
- **Small gotchas (<200 tokens):** inline in the relevant rule file. Lead with the rule, then **Why:** / **How to apply:**.
- **Larger context** (multi-paragraph, decision trees, code samples): `docs/domain/<topic>.md` (engineering knowledge, distinct from `docs/design/` which is game design).
- Game-design knowledge belongs in `docs/design/` or as a GitHub Issue (`design` label) — not inline here.
