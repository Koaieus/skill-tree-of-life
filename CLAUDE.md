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

### Stat system (`stats_system/`)

Stats are central to this game. See `.claude/rules/stats-system.md` for the full reference (IDs, pipeline, gotchas) — keep it current when the system changes.

PoE-style modifier pipeline: `(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`. SET short-circuits everything.

Key files:
- `stats_system/stat_board.gd` — entity's stat container; `add_modifier` / `remove_modifier` / `get_value(id)`
- `stats_system/stat.gd` — runtime stat instance (ScalarStat / PoolStat / SkillPointStat)
- `stats_system/stat_modifier_def.gd` — static modifier atom (stat_id + operation + value)
- `stats_system/derived_modifier_def.gd` — formula-computed modifier; **must not be shared across entities**
- `stats_system/formulas/` — LinearFormula, ExpressionFormula
- `stats_system/list/` — 20 `.tres` StatDef resources (one per stat)
- `entity/default_entity_board.tres` — template board with all stats + intrinsic scaling modifiers

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

## Game mechanics in one screen

A mental model for fast routing and answering questions. Status: most rules are designed, most numbers are not calibrated. Full detail lives in `docs/design/` (see index below).

**The pitch.** The skill tree IS the world. Entities (player + NPCs) own connected **induced** subgraphs of allocated nodes on one shared, procedurally generated planar graph (300–1000 nodes). Turn-based, initiative-driven. Roguelite — a run is a level chain ending in a Breakout that recurses you one fractal level up.

**Entity = connected induced subgraph + a Core.** The Core is a portable node the entity "sits on"; it carries modifiers like any node and also radiates an *aura* over nearby owned nodes (range/shape varies by class). Each allocated node contributes its `StatModifier`s to the entity's stat board. Allocating costs 1 SP; deallocating refunds. Lost-to-attack nodes **reserve** SP (no refund), recovered via `heal/turn`. Killing a **cut vertex** islands an arm; orphans dissolve unless Lifeline/Lifelink saves them.

**Six color attributes (base ≈ 10 each).** Attack: **R/STR** (melee), **G/DEX** (ranged), **B/INT** (magic). Utility: **W/CON** (durability — node HP, armor weight), **Gold/WIS** (XP / economy), **Purple/PER** (vision + sensor). The scaling spine: `outgoing = base + attribute//10 × instances`, defense applied once per target.

**Three attack modes, each weaponizes a different graph primitive.**
- **Ranged (G/DEX)** — every owned **leaf** (degree 1) in euclidean range volleys one target. `DEX//10` per firing leaf.
- **Magic (B/INT)** — degree-gates spell tier (hubs cast bigger; self-loops give +2 degree and are prized casting stations). Propagation along edges; potency scales with `INT//10`; reach is rare (`bonus_hop_count`). `attack_range` doesn't apply.
- **Melee (R/STR) — the phantom blade.** Pick a connected set of owned nodes (size `STR//10+1`); a 1:1 copy is swung pivoted at one node. Rigidity emerges from triangulation (tensegrity); chain = whippy, triangulated = rigid cleaver.

**Turn structure.** Initiative ticks until 100 → entity acts. Three phases: **Deployment → Battle → Consolidation**, single SP pool (no "temp SP" — the phase IS the temp/permanent flag). **2 `action_points`** per turn by default. The second action is load-bearing because **`node_health` resets at each owner's turn start** — survivability is a *per-round focus-soak gate*, not chipping over turns. The Core has a recharging shield over a persistent `health` pool; **death = `health` depletion**, not core-node loss.

**Progression.** Three growth axes are the same act: allocate nodes (territory + modifiers), level up (+1 SP cap + draft 1 of 3–5 permanent core modifiers; pool size = `3 + luck`), loot kills (STEAL onto core, PROLIFERATE over nearby nodes). Each level ends in a **Breakout**: destroy all **Tethers** + kill the guardian → the field collapses into one node, your new starter one fractal level up. End-game = the **Apex Entity** (Ophanim ring). Between runs: a **Metagame** hub + meta skill tree; allocating a meta node *is* what crashes you into a run; commit-on-completion.

**Classes (7 + sketches).** Class = starting stat weights + an aura rule (+ occasional unique mechanic). Aura *shape* (near / shell / far) is most of identity. Roster: Allround, Predator (BLITZ-steal), Bulwark (`damage_floor` floor), Ninja (deallocation burst), Hive (Lifelink pods), Halo (shell aura + thorns), Serpent (far-in-hops-near-in-space). Plus Edgelord (edge ops; last to unlock), Frontier, Harvester.

**Stat system (v2 in flight).** `StatDefinition` resources keyed by `StringName`, `RuntimeStat` objects, `StatRegistry` autoload. Operators apply PoE-style: `ADD_FLAT → ADD_PERCENT → MULTIPLY`. Adding a stat = define one resource. v1 (GDScript-as-key) still ships; prefer v2 patterns for new stats.

**Open holes worth knowing about.** The **defensive curve** and the per-round focus count are uncalibrated — GDD §11a and `docs/design/combat_worked_examples.md` are the agreed plan to lock the battle formula. Magic propagation rules + Relay are still open (blocks several systems). Most class numbers await calibration.

## Design docs index

Canonical entry points: **`docs/GDD.md`** (master GDD — pitch, core loop, roadmap) and **`docs/design/index.md`** (the design-doc index with reading order). Per-doc open questions live at the bottom of each doc; tracked work lives in **GitHub Issues** (see below).

| Doc | What it covers |
|---|---|
| `docs/GDD.md` | Master GDD — pitch, core loop, the supergraph, entities, combat summary, classes, progression, open questions, roadmap |
| `docs/design/index.md` | Index + reading order for the design docs below |
| `docs/design/lore.md` | Narrative, acts, the Fairy, graph theology, Field/Tethers/Breakout, tone, visual language |
| `docs/design/first_session_walkthrough.md` | Spoiler-free, second-person UX walkthrough — boot → first cut-vertex snipe; calls out funny/questionable beats |
| `docs/design/combat_system.md` | Damage pipeline (//10 spine), six-color triangle, ranged/magic/melee (phantom blade), degree→offense, self-loops, three-phase turn, islands, Breakout, loot |
| `docs/design/combat_worked_examples.md` | Worked fights in real numbers; tempo axiom; defense-function handoff |
| `docs/design/core_classes.md` | Entity core classes (Allround, Predator, Bulwark, Ninja, Hive, Halo, Serpent, Frontier, Harvester, Edgelord) |
| `docs/design/stat_system.md` | Stat architecture (v2 direction), modifier pipeline, canonical stat vocabulary |
| `docs/design/entity_stat_board_prototype.md` | Prototype stat values, SP accounting, damage formula, class stat variations |
| `docs/design/metagame.md` | Hub between runs, meta skill tree, commit-on-completion, The Way Out |
| `docs/design/skill_node_addons.md` | Node addons (Armor Ring, Buffer, Gate, Relay, Anti-Magic, etc.), Tech Seeds |
| `docs/design/skill_node_specializations.md` | Node specializations (Corrupted, Crystallized, Anchor) |
| `docs/design/spells.md` | Spell catalogue — identity and propagation for all Blue (INT/magic) spells |

## Issue tracking

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`). Project-specific labels: **`core`** (core game feature), **`design`** (game-design decision/investigation). Plus the default GitHub set (`bug`, `enhancement`, `documentation`, `question`, `good first issue`, `help wanted`, `duplicate`, `invalid`, `wontfix`).

## Godot conventions used here

- `@tool` is used on `TreeNode`, `TreeEntity`, and `Player` so they run in the editor.
- `%NodeName` (unique name) shorthand is used for child node access in several scenes.
- `call_deferred` / `await` patterns are common for post-ready initialization (e.g. `Game.game_ready` signal).
- Stat keys are currently `GDScript` objects (`get_script()`) — do not rename or move stat files without updating all `StatModifier.stat_key` references.

## Knowledge accumulation

When you learn something non-obvious about this project — a gotcha, a convention that isn't visible from the code, a workflow surprise, a design decision the GDD doesn't capture — **proactively offer to write it down**. Don't wait to be asked.

Sizing discipline:
- **Small rules / gotchas (<200 tokens)** live inline in this file under whatever section fits (Architecture, Godot conventions, etc.). Format: lead with the rule, then **Why:** and **How to apply:** so future-you can judge edge cases instead of blindly following.
- **Larger context** (multi-paragraph mechanics, decision trees, code samples, refactor playbooks) lives in `docs/domain/<topic>.md`. This is distinct from `docs/design/` — `docs/design/` is the *game's* design (lore, balance, mechanics specs), `docs/domain/` is *engineering* knowledge for agents working on this codebase.
- **Project-wide rules** that don't slot under any existing section live in CLAUDE.md as a top-level entry, no scoping needed.
- When an inline rule grows past ~200 tokens, **graduate it to `docs/domain/`** and leave a one-line breadcrumb here: `- See [docs/domain/<topic>.md](docs/domain/<topic>.md) for X`.

Audit every few turns: scan CLAUDE.md for rules that have ballooned and propose graduation. Goal: this file stays scannable — ~200 lines max — while the rule-base scales.

Game-design knowledge (lore, mechanics, balance numbers) belongs in `docs/design/`, not `docs/domain/` and not inline here. If a "rule" you're tempted to save is really a design clarification, raise it as a doc update or a GitHub Issue (`design` label) instead.
