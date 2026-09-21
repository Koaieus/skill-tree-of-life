# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Skill Tree of Life** — a Godot 4.7 game where the skill tree *is* the game. Entities (players, NPCs) live on a graph of skill nodes, allocating nodes to expand territory and stats. Turn-based, initiative-driven. See `docs/GDD.md` for the full pitch and `docs/design/index.md` for design doc reading order.

## Delegating to subagents

**Always pass `model: "haiku"` on `Explore` agent calls** — an omitted `model` inherits the parent's, so a forgotten pin makes an Opus orchestrator spawn an Opus grep.

## Running the Game

`mise install` is the whole setup (`mise.toml` pins the engine — exactly, it decides whether a `.tscn` loads — plus `gh` and python); msdfgen for the font pipeline is `mise run tools:bootstrap`.

```
godot --editor .                                  # open project in editor
godot --path . scenes/dev_sandbox.tscn            # hand-authored, fully baked — instant
godot --path . scenes/first_level_sandbox.tscn    # THE one to reach for: a real 800-node
                                                  # playthrough, run authored in session/runs/
godot --path . scenes/procgen_play_sandbox.tscn   # small procgen proof-of-concept, 120 nodes
```

`run/main_scene` is `scenes/meta/meta_root.tscn` — the frontmatter menu, where
an exported build and a bare `godot --path .` (or F5) start. Launch sandboxes by
path, as above; never repoint the main scene (why: `docs/domain/godot-workflow.md`).

`scenes/level.tscn` is the shipped level and refuses to launch without a run in
`GameSession`; the sandboxes are that scene plus a `RunBootstrap` child holding
an authored `RunConfig`.

No build step or lint tool. Tests are GUT, driven through mise:

```
mise run test                                  # full suite, headless (reads .gutconfig.json)
mise run test:one -- res://test/unit/test_smoke.gd   # a single script
mise run test:dir -- res://test/unit/          # a directory
mise run check                                 # headless compile-check of every script + shader
mise run check-shaders                         # the shader half alone: compile-checks every .gdshader in the tree
mise run refresh                               # editor/class-cache refresh + a verdict on what it changed
mise run mp:e2e                                # two processes play the shipped lobby to a verdict
                                               # (~30s) — the gate for network/ session/ command/
```

The full suite (~45s wall, sharded; `GUT_SHARDS=1` is the ~6-minute single
process) is a **gate, not a feedback loop** — cheap in wall clock, not in the
context its output costs. Earn it **once per unit of work**, at final green,
never to explore. Iterate on the cheap ladder: `check` (~20s) → `test:one` →
`test:dir` → the suite. `mise run test` prints a verdict and keeps the full log
at `.godot/gut-last.log` plus junit XML — see `.claude/rules/testing.md`.

Each level scene extends `scenes/game_root.tscn` (the composition root); subclasses populate content via the `_setup_level()` hook.

## Architecture

`GameRoot` (`scenes/game_root.gd`) — per-level composition root; mounts VFX, wires systems, calls `_setup_level()`, then `HudRoot.compose(self)`. Subclass + override `_setup_level()` to author or generate level content.
`HudRoot` (`ui/hud/hud_root.gd`) — the "Arcane Terminal" HUD, sole UI layer; clusters `bind()` their own deps, cross-system deps arrive through one `compose(game_root)` split by lifetime (`bind_systems()` per level, `rebind_player()` per hot-seat handover).
`Graph` (`graph/graph.gd`) — owns `SkillNode`s + `Edge`s + `entities_container`; pure topology, structural signals.
`Entity` (`entity/entity.gd`) — players and NPCs share the class; ownership is set by `AllocationSystem`. Composes a `CoreClass` (`entity/core/`) — identity modifiers + an `on_turn_started` hook.
`SeatPolicy` (`session/seat_policy.gd`) — the per-machine half of a run's setup (who this machine plays, whose eyes it draws with); run shape is the roster's half. See `docs/domain/seat-policy.md`.
`Navigator` (`graph/navigator.gd`) — full-graph `AStar2D` mirror; `EntityNavigator` is the per-entity mirror for cut-vertex / islanding queries.
`TurnManager` (`systems/turn_manager.gd`) — initiative ticks to 100 → entity acts; `end_turn()` deducts 100. See `.claude/rules/turn-manager.md`.
`AllocationSystem` (`systems/allocation_system.gd`) — `allocate` / `deallocate` (gated) + `force_allocate` / `force_deallocate` (primitives). See `docs/domain/allocation_system.md`.
`BattleSystem` (`systems/battle_system.gd`) — owns the active `AttackPlan`; `launch_attack` submits a command to `CommandApplier`, which replays the resolved `AttackRecord` on the reveal clock. See `docs/domain/attack_plan_system.md`.
`VisionSystem` (`systems/vision_system.gd`) — fog of war; reads owned subgraph + per-entity `vision_range` / `sensor_range`. See `docs/domain/vision-system.md`.
`LootSystem` (`systems/loot_system.gd`) — killing-blow XP, tempo, and a relic on the victim's former core; snapshots on `Events.entity_dying`, before the corpse is stripped. See `docs/domain/loot-system.md`.
`StatBoard` (`stats_system/`) — PoE-style modifier pipeline. See `.claude/rules/stats-system.md` — **update it when the stat system changes.**
`VictorySystem` (`systems/victory_system.gd`) — sole emitter of `Events.run_ended(RunOutcome)`; owns the *when* and the *once*, the swappable `VictoryCondition` owns the *what*. See `docs/domain/victory-system.md`.
`GraphProcgen` (`procgen/graph_procgen.gd`) — static pipeline; `generate(config, graph)` returns nodes + starting_nodes. See `docs/domain/procgen.md` (topology), `docs/domain/procgen-v4.md` (content).

Spawning runtime entities: in `_setup_level()`, call `spawn_entity(name, color, core_location, core_class)`. See `scenes/procgen_play_sandbox.gd`.

## Autoloads (registered in `project.godot`)

`SceneTransition`, `SceneDirector` (routing + async loading; `MetaRoot` and the menu shell go through `.goto`), `Settings`, `BuildInfo`, `StatRegistry`, `DebugClipboard` (press `c` over a SkillNode to copy its full state) — and three that matter for game logic:

| Singleton | Purpose |
|---|---|
| `Events` | Global signal bus (`skill_node_depleted`, `entity_dying`, `run_ended`, …) |
| `GameSession` | The live run — `RunConfig`, `ParticipantRoster`, `RunOutcome`; resolves the procgen seed **exactly once** up front (`.claude/rules/game-session.md`) |
| `Wire` | The LAN socket + the repo's single `@rpc`, at `/root/Wire`. See `docs/domain/multiplayer-harness.md` |

## Issue tracking

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`); board via `mise gh-project -- list|add|status|…`. **`add` already lands the issue in `Backlog`** — only call `status` after for a different lane.

**The status ladder is the pipeline** — `Backlog` → `Needs design` (the `/swarmify` inbox) → `Ready` → `In progress` → `In review` → `Done`. `Ready` *is* the swarm queue and **a drone never touches a non-`Ready` issue**; what to pull first is the live GitHub milestone, never a prose file — the board is authoritative for status, dependencies and what shipped.

**Reading an issue is two calls** — `gh issue view <n>` (body) and `--comments` (comments only; silent exit 0 on none), and the comments usually hold the decisions. **Never `gh --body "..."` with backticks** — heredoc to a file, `--body-file`. **Attribute owner decisions to the owner, verbatim**, dated. **A parent never carries work** — a hub's status is derived from its children, never set by hand.

Board commands, the hub rules, roadmap fields, sub-issues, and why attribution is load-bearing: **`docs/domain/issue-workflow.md`**.

## Godot conventions

`@tool` on `SkillNode`, `Entity`, `Graph` (they run in the editor); `%NodeName` for scene-child access (GameRoot reads systems via `%VisionSystem` etc.); `call_deferred` / `await` for post-ready init.

## Knowledge accumulation

When you learn something non-obvious — a gotcha, a hidden constraint, a workflow surprise — **offer to write it down**; agents under-do this slightly, and a little too little still beats a little too much. Each kind of knowledge has one home:

- **Gotcha tied to files** → `.claude/rules/<module>.md`, scoped with a `paths:` glob (a rule with no `paths:` is always-on and taxes every session). Small: the rule, then **Why:** / **How to apply:**. Long (decision trees, code samples) → `docs/domain/<topic>.md` with a one-line pointer from the rule.
- **Claim every session must see** → a **breadcrule**: its own unscoped `.claude/rules/<topic>.md`, one line, `<claim>. See docs/domain/<topic>.md`. Never a paragraph, never a line in CLAUDE.md — this file orients and is otherwise never edited; unscoped rules are its composable extensions. See `docs/domain/breadcrules.md`.
- **A settled architectural call** → an ADR in `docs/adr/` (the `adr` skill). `/swarmify` produces most of these — some are firm owner calls, some tentative picks between comparable options; record which, so a later pass knows what may be revisited.
- **Why a skill/agent says what it says** → its charter, `docs/charters/<name>.md`; the instruction file is derived from it. See `docs/charters/README.md`.
- **Game design** → `docs/design/` or a `design`-labelled issue. Never inline here.
- **Code comments state the contract** — what, invariant, gotcha — never history or an issue number (a decision's home cites the issue). Past ~12 lines, move it to `docs/domain/` and leave a pointer.
- **`mise run rules-hygiene`** reports tier budgets, dead crumbs and globs, comment essays — run it after touching a rule, as `gh-project hygiene` after touching the board.

## Working in this repo

The main checkout is a **shared, un-worktree'd surface** — other agents may be
working there, possibly with uncommitted WIP. If tests suddenly fail there,
check what was happening before sinking time into it — it may be step one of
someone's refactor; follow its lead and confirm alignment with the user.

Prefer a clean codebase: refactor into scenes, DI via `@export`ed vars,
inherited scenes where they earn their keep. Take it to the next level rather
than the minimum. Keep to common conventions for YAGNI's sake — but planning
ahead pays too. Case-by-case care works best.
