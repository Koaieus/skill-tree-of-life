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

The full suite (~45s) is a **gate, not a feedback loop**: earn it once per
unit of work, at final green. Iterate on `check` (~20s) → `test:one` →
`test:dir` → the suite. Verdict on stdout, full log at `.godot/gut-last.log`
— see `.claude/rules/testing.md`.

Each level scene extends `scenes/game_root.tscn` (the composition root); subclasses populate content via the `_setup_level()` hook.

## Architecture

`GameRoot` (`scenes/game_root.gd`) is the per-level composition root: mounts
VFX, wires systems, calls `_setup_level()`, then `HudRoot.compose(self)`;
`HudRoot` (`ui/hud/hud_root.gd`) is the sole UI layer. Spawn a runtime entity
from `_setup_level()` with `spawn_entity(name, color, core_location, core_class)`.

Where to read next, by system (one line each in `docs/domain/system-map.md`):
`Graph`/`Navigator` → `graph/`; `Entity` + `CoreClass` → `entity/`;
`SeatPolicy` → seat-policy.md; `TurnManager` → `.claude/rules/turn-manager.md`;
`AllocationSystem` → allocation_system.md; `BattleSystem` →
attack_plan_system.md; `VisionSystem` → vision-system.md; `LootSystem` →
loot-system.md; `StatBoard` → `.claude/rules/stats-system.md` (**update it when
the stat system changes**); `VictorySystem` → victory-system.md;
`GraphProcgen` → procgen.md + procgen-v4.md. Unqualified names are
`docs/domain/`.

## Autoloads (registered in `project.godot`)

`SceneTransition`, `SceneDirector` (routing + async loading; `MetaRoot` and the menu shell go through `.goto`), `Settings`, `BuildInfo`, `StatRegistry`, `DebugClipboard` (press `c` over a SkillNode to copy its full state) — and three that matter for game logic:

| Singleton | Purpose |
|---|---|
| `Events` | Global signal bus (`skill_node_depleted`, `entity_dying`, `run_ended`, …) |
| `GameSession` | The live run — `RunConfig`, `ParticipantRoster`, `RunOutcome`; resolves the procgen seed **exactly once** up front (`.claude/rules/game-session.md`) |
| `Wire` | The LAN socket + the repo's single `@rpc`, at `/root/Wire`. See `docs/domain/multiplayer-harness.md` |

## Issue tracking

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`); board via `mise
gh-project -- list|status|…`. The board is authoritative for status,
dependencies and what shipped; its lanes `Backlog` → `Needs design` → `Ready`
→ `In progress` → `In review` → `Done` are the pipeline and **`Ready` is the
only lane a drone pulls from**. Read an issue as `gh issue view <n>` plus
`--comments` (the decisions live there). Everything else — a new issue joins
`Backlog` by itself, `--body-file` never inline backticks, owner decisions
attributed verbatim and dated, hubs never carry work — is in
**`docs/domain/issue-workflow.md`**.

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
