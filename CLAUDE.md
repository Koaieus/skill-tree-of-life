# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Skill Tree of Life** — a Godot 4.7 game where the skill tree *is* the game. Entities (players, NPCs) live on a graph of skill nodes, allocating nodes to expand territory and stats. Turn-based, initiative-driven. See `docs/GDD.md` for the full pitch and `docs/design/index.md` for design doc reading order.

## Delegating to subagents

**Always pass `model: "haiku"` on `Explore` agent calls.** There is no cheap default to fall back on: an omitted `model` inherits the *parent's*, so a forgotten pin makes an Opus orchestrator spawn an Opus grep. Haiku is what read-only search (finding files, grepping symbols) wants anyway.

## Running the Game

```
godot --editor .                          # open project in editor
godot --path . scenes/dev_sandbox.tscn    # hand-authored sandbox (player + small graph)
godot --path . scenes/procgen_play_sandbox.tscn   # procgen level + player + AI starters
```

No build step or lint tool. Tests are GUT, driven through mise:

```
mise run test                                  # full suite, headless (reads .gutconfig.json)
mise run test:one -- res://test/unit/test_smoke.gd   # a single script
mise run test:dir -- res://test/unit/          # a directory
mise run check                                 # headless compile-check of every script
mise run refresh                               # editor/class-cache refresh + a verdict on what it changed
```

Each level scene extends `scenes/game_root.tscn` (the composition root); subclasses populate content via the `_setup_level()` hook.

## Architecture

`GameRoot` (`scenes/game_root.gd`) — per-level composition root; mounts VFX, wires systems, calls `_setup_level()`, then `HudRoot.compose(self)`. Subclass + override `_setup_level()` to author or generate level content. Spawn entities via `spawn_entity(name, color, core_location, core_class)`.
`HudRoot` (`ui/hud/hud_root.gd`) — the "Arcane Terminal" HUD, sole UI layer since #118 (replaced the old UIRoot/StatsPanel/ContextPanel, all deleted). Anchors six design clusters (Hero/Attributes/TurnResources left column, CombatReadout/NodeInspectorCard right column, CommandTray bottom-center, ActionCluster bottom-right, XpTrack top-center with InitiativeBar hanging beneath it) plus AnnouncementLayer FX (variant-routed TitleBand/CalloutBand, #135) and TooltipFan/SpellTooltip/PauseMenu/StatBoardOverlay mounts. Each cluster gets deps via its own scene-local `bind()`; cross-system deps flow through one `compose(game_root)` call.
`Graph` (`graph/graph.gd`) — owns `SkillNode`s + `Edge`s + `entities_container`; pure topology, structural signals.
`Entity` (`entity/entity.gd`) — players and NPCs use the same class; ownership is set by `AllocationSystem`. Composes a `CoreClass` (`entity/core/`) that brands the entity with identity modifiers + an `on_turn_started` hook; `BalancedCore` is the +10 STR/DEX/INT baseline.
`Navigator` (`graph/navigator.gd`) — full-graph `AStar2D` mirror; `EntityNavigator` (`entity/entity_navigator.gd`) is the per-entity subgraph mirror used for cut-vertex / islanding queries.
`TurnManager` (`systems/turn_manager.gd`) — initiative ticks to 100 → entity acts (single implicit phase — intent is by input channel, not phase gates); `end_turn()` deducts 100. See `.claude/rules/turn-manager.md`.
`AllocationSystem` (`systems/allocation_system.gd`) — `allocate` / `deallocate` (gated) + `force_allocate` / `force_deallocate` (primitives). See `docs/domain/allocation_system.md`.
`BattleSystem` (`systems/battle_system.gd`) — owns active `AttackPlan`, runs `launch_attack` (resolve → VFX await → AP deduction), drives forced-dealloc cascade. See `docs/domain/attack_plan_system.md`.
`VisionSystem` (`systems/vision_system.gd`) — fog of war; reads owned subgraph + per-entity `vision_range` / `sensor_range`. See `docs/domain/vision-system.md`.
`LootSystem` (`systems/loot_system.gd`) — killing-blow rewards: XP to the killer (#68) + a `SkillDustAddon` relic on the victim's former core (#69). Resolves the killer from its injected `turn_manager`; reacts to the pre-cleanup `Events.entity_dying` phase (corpse still owns its nodes) so it snapshots before AllocationSystem's `entity_died` strip. See `docs/domain/loot-system.md`.
`StatBoard` (`stats_system/`) — PoE-style modifier pipeline. See `.claude/rules/stats-system.md` for IDs, pipeline, gotchas — **update it when the stat system changes.**
`VictorySystem` (`systems/victory_system.gd`) — the sole decider that a run ended, and the sole emitter of `Events.run_ended(RunOutcome)`. Owns the *when* (evaluate on death, coalesced one-per-frame) and the *once* (the latch); the swappable `VictoryCondition` resource owns the *what*, with `LastCampStandingCondition` the default. Inertness is authored on `Faction`, false only on `blocker.tres`, as two deliberately separate flags: `counts_for_victory` (can end a run) and `targeted_by_ai` (worth an NPC's AP, filtered in `AiRecon.visible_enemy_nodes` — never in `attitude_to`, which must keep blockers HOSTILE so the player can clear them). See `docs/domain/victory-system.md`.
`GraphProcgen` (`procgen/graph_procgen.gd`) — static pipeline; `generate(config, graph)` returns nodes + starting_nodes. See `docs/domain/procgen.md` (topology) and `docs/domain/procgen-v4.md` (content: StatPool + phased draw).

Spawning runtime entities: subclass `GameRoot`, override `_setup_level()`, call `spawn_entity(name, color, core_location, core_class)` — it duplicates the default stat board, parents under `graph.entities_container`, force-allocates the core node, and assigns the class. See `scenes/procgen_play_sandbox.gd`.

## Autoloads (registered in `project.godot`)

| Singleton | Purpose |
|---|---|
| `Boot` | Release-build entry point — on `OS.has_feature("release")` swaps to `first_level_sandbox`. No-op in the editor. |
| `SceneTransition` | Fade in/out + loading progress bar |
| `SceneDirector` | Scene routing + async loading. Absorbed the zero-caller `SceneLoader` (#212); `MetaRoot` and the menu shell route through `SceneDirector.goto` |
| `Settings` | `GameSettings` + `ConfigFile` persistence, surfaced by the reflected settings menu |
| `BuildInfo` | Seed / branch / worktree, shown in the pause-menu footer |
| `Events` | Global signal bus (`skill_node_depleted`, etc.) |
| `StatRegistry` | StatDef lookup by id |
| `DebugClipboard` | Press `c` while hovering a SkillNode to copy its full state (archetype, owner, hp, modifiers, addons) to the system clipboard |

## Design docs

Entry points: `docs/GDD.md` (master GDD) · `docs/design/index.md` (full index with reading order).

## Issue tracking

GitHub Issues via `gh` (repo `Koaieus/skill-tree-of-life`). Labels: `core`, `design`, `blocked` (open upstream fork), plus defaults. Project board (kanban): `mise gh-project -- list|add|status|priority|size`. `list [backlog|needs-design|ready|in-progress|in-review|done|all]` shows a column — that's how an agent finds work to pick up; add `--json` (with `mise run --quiet`) for machine-readable output. See `.mise/tasks/gh-project`.

**The status ladder is the pipeline.** `Backlog` (not scheduled) → `Needs design` (scheduled, open forks — the `/swarmify` inbox) → `Ready` (a drone can take it) → `In progress` → `In review` → `Done`. The design gate: a forked issue sits in `needs-design` → `/swarmify #n` (settle forks *with the user*, write acceptance, split hubs into file-disjoint children) → `status <n> ready` → `swarm`/`warp` executes. **A drone never touches a non-`Ready` issue.** `Ready` *is* the swarm queue — there is no `swarmable` label (retired 2026-08-02: a second source of truth for what the status already said, and it rotted both ways). Standing hub queue: issue **#261**.

**`Ready` and `Needs design` are filtered by [docs/FOCUS.md](docs/FOCUS.md).** A lane item that is `Ready` is takeable; anything else sitting in `Ready` is *scheduled-eligible but not scheduled*, and a drone must not pull it. Same for `Needs design` — being in that column means "forks are open", not "work on this next". FOCUS names the five ordered lanes and the WIP limit; when it and a status field disagree, FOCUS wins. This exists because status columns alone couldn't stop scope drift: they say what a thing's *state* is, never what's *next*.

**Roadmap + hygiene.** `mise gh-project -- roadmap` prints milestone swim-lanes with epic progress; `milestone|target|start|estimate <n> [val]` set roadmap fields; `label <n> add|rm <name>` flips a label. `hygiene [--json]` reports board invariant violations and fixes nothing — run it whenever you look at the board. The headline invariant: **`Backlog` means "no live parent."** A child may sit at any pipeline stage under an `In progress` hub (that's what grinding a hub down looks like), but never parked in `Backlog`, where nobody pulls from.

**Sub-issues:** the repo uses the parent/sub-issue model. File a child under its epic with `gh issue create --parent <parent-number> …` (gh ≥ 2.9x) — this nests it, distinct from a `Closes #` trailer.

**Never pass `gh --body "..."` with backticks** — the shell runs command substitution and silently deletes the span, publishing mangled text with no error. Write a heredoc to the scratchpad and use `--body-file`.

**RTFC — read the fucking comments.** When working an issue, read its comments, not just the body: they often hold the actual decisions, pointers, new direction, or bug reports that outweigh the original body. **`gh issue view <n>` prints the body; `--comments` prints ONLY the comments** (gh 2.97) — reading an issue is *two* calls, and `--comments` on an issue with none gives empty output and exit 0, which is not a broken pager. `mise.toml` exports `GH_PAGER=cat` repo-wide, so `gh` never pages even under a pty; reaching for `--json` to dodge a suspected hang just makes you guess at field names.

**Attribute owner decisions to the owner, verbatim.** Nearly every issue body and comment here was written by an agent, so when you write up a fork the owner settled, quote their words and label it an owner call (`**Owner call 2026-08-21:** "…"`). Never launder it into your own reasoning.

**Why:** agents resolve contradictions by authority — an owner call outranks a later comment, which outranks a maintained doc, which outranks an agent-written body. A decision written up as an agent's own conclusion re-enters the record at the *bottom* of that ladder, so the next agent is free to argue with it and the record degrades into competing confident opinions. Attribution is what makes a decision stick.

**How to apply:** quote the owner; date it; say what it supersedes if it reverses something. When you hit a contradiction you cannot resolve by that ladder, ask the owner — don't pick a side, and don't write a new comment arguing with an old one.

## Godot conventions

- `@tool` on `SkillNode`, `Entity`, `Graph` — they run in the editor.
- `%NodeName` (unique name) for child node access in scenes; GameRoot reads systems via `%PlayerInputController`, `%VisionSystem`, etc.
- `call_deferred` / `await` for post-ready init.

## Knowledge accumulation

When you learn something non-obvious — a gotcha, a hidden constraint, a workflow surprise — **proactively offer to write it down**.

- **Rule files** live in `.claude/rules/<module>.md`. If you hit a gotcha while working on a module, check if a rule file exists; create or update it. Keep rules current — a stale rule is worse than no rule. **Scope it** with a `paths:` glob so it loads only when its files are read — a rule with no `paths:` is always-on and taxes every session. See `docs/domain/breadcrules.md`.
- **Small gotchas (<200 tokens):** inline in the relevant rule file. Lead with the rule, then **Why:** / **How to apply:**.
- **Breadcrule** — when a pointer must sit in the always-on tier, make it its own `.claude/rules/<topic>.md` file (no `paths:` frontmatter) whose whole body is one line stating the claim *and* linking the doc (`<claim>. See docs/domain/<topic>.md`); never a paragraph, never a line pasted into CLAUDE.md. See `docs/domain/breadcrules.md`.
- **Larger context** (multi-paragraph, decision trees, code samples): `docs/domain/<topic>.md` (engineering knowledge, distinct from `docs/design/` which is game design).
- **`mise run rules-hygiene`** reports rule-tier violations (always-on budget, oversized
  scoped rules, dead crumbs, dead `paths:` globs) and fixes nothing — run it whenever you
  add or edit a rule, same as `gh-project hygiene` for the board.
- Game-design knowledge belongs in `docs/design/` or as a GitHub Issue (`design` label) — not inline here.

## Working in this repo

The main checkout is a **shared, un-worktree'd surface** — other agents may be
working there directly, or there may be uncommitted WIP. If tests suddenly start
failing there, don't sink time into it; you can usually still land another part.
Fix what's in your scope or is a quick win, but check what was happening first —
it may be step one of someone's refactor, in which case follow its lead and
confirm alignment with the user.

Prefer a clean codebase: refactor into scenes, DI via `@export`ed vars, inherited
scenes where they earn their keep. Take it to the next level rather than the
minimum. Keep to common conventions for YAGNI's sake — but the opposite of YAGNI
pays off too, so plan ahead. Case-by-case care works best.
