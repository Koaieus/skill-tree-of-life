# Skill Tree of Life

> *What if you opened the skill tree of an RPG — and got trapped inside it?
> And what if the skill tree **is** the game?*

A turn-based, roguelite, PvP-on-a-skill-tree game in Godot 4.4. Player and enemies are **entities** — connected subgraphs of allocated nodes — living on a shared procedurally generated skill tree. You expand your subgraph by allocating nodes (claiming their stat modifiers and territory), and you attack enemies by *severing* theirs: hit a **cut vertex** to break an entity into pieces and watch the orphaned arms dissolve. Kill the **Apex** (a vast ring at the top of the level), break out, compress the entire level into a single node one fractal layer up, and do it again.

**Status:** design-heavy prototype. The Godot project is a sandbox for ideas — many systems are stubbed, none are balanced. The design (`docs/`) leads; the code follows. Expect the implementation to be rebuilt once the design lands. See [docs/GDD.md](docs/GDD.md) for the full pitch.

---

## The core fantasy in one screen

- **You are your subgraph.** Allocate adjacent nodes (1 SP each) to grow; your stats are the sum of every modifier on every node you own, plus your Core.
- **Topology is loadout.** Leaves (degree 1) are ranged firing ports. Hubs (high degree) are powerful spell casters. A connected set of your nodes can be swung as a **phantom blade** in melee — rigidity falls out of triangulation.
- **Attack the structure, not the HP bar.** Kill a cut vertex on an enemy and any arm severed from their Core dissolves. Dismemberment is the core combat fantasy.
- **The skill tree itself is procedurally generated.** Hundreds of nodes per level, six attribute colours (STR/DEX/INT/CON/WIS/PER), archetype clusters, themed topologies (Tech Strip, The Web, The Spiral, …).
- **Breakout = fractal compression.** Clear the Apex, the entire level collapses into a single starter node one level up. The cosmos re-edges it. Begin again, bigger.

---

## Running it

Open the project in Godot 4.4 (no build step, no test runner beyond GUT):

```
godot --editor .                                  # open in editor
godot --path . scenes/dev_sandbox.tscn            # hand-authored sandbox
godot --path . scenes/procgen_play_sandbox.tscn   # procgen level + player + AI
godot --path . scenes/dev_addon_gallery.tscn      # dev: grid of all addons
```

Tests (GUT):

```
mise run test                                     # full suite
mise run test:one -- res://test/unit/test_foo.gd  # single file
```

---

## Code architecture (one-pager)

Every level scene extends [`scenes/game_root.gd`](scenes/game_root.gd) — the composition root. Subclasses override `_setup_level()` to populate content.

| Module | Role |
|---|---|
| [`scenes/game_root.gd`](scenes/game_root.gd) | Composition root. Mounts VFX, wires systems, spawns entities. |
| [`graph/graph.gd`](graph/graph.gd) | The supergraph: `SkillNode`s + `Edge`s + entities container. Pure topology. |
| [`graph/navigator.gd`](graph/navigator.gd) | Full-graph `AStar2D` mirror for pathing & vision queries. |
| [`entity/entity.gd`](entity/entity.gd) | Player and NPCs use one class; ownership is set by the allocation system. |
| [`systems/turn_manager.gd`](systems/turn_manager.gd) | Initiative clock + three-phase turns: `CONTRACT → EXPAND → BATTLE`. |
| [`systems/allocation_system.gd`](systems/allocation_system.gd) | `allocate`/`deallocate` (gated by phase) + force primitives. |
| [`systems/battle_system.gd`](systems/battle_system.gd) | Resolves attacks, drives the forced-deallocation cascade (islanding). |
| [`systems/vision_system.gd`](systems/vision_system.gd) | Fog of war: euclidean `vision_range` + hops-based `sensor_range`. |
| [`stats_system/`](stats_system/) | PoE-style modifier pipeline (`SET` → `ADD_BASE` → `INCREASE` → `MULTIPLY` → `ADD_BONUS`). Pool stats, local (per-node) stats, derived modifiers. |
| [`procgen/graph_procgen.gd`](procgen/graph_procgen.gd) | Static pipeline: `generate(config, graph)` → nodes + starting nodes. |

Domain notes — `.claude/rules/*.md` and `docs/domain/*.md` carry the gotchas. Notably:

- [`.claude/rules/stats-system.md`](.claude/rules/stats-system.md) — modifier pipeline, pool stats (`current` vs modifier-computed max), SP accounting (`current` / `wounded` / `staked` / derived `used`), intrinsic scaling table.
- [`.claude/rules/turn-manager.md`](.claude/rules/turn-manager.md) — phase gates, initiative ticking, turn-start upkeep.
- [`.claude/rules/godot-workflow.md`](.claude/rules/godot-workflow.md) — when to refresh the class cache and what scenes/`.tres` files the editor can silently mutate.
- [`docs/domain/allocation_system.md`](docs/domain/allocation_system.md), [`docs/domain/attack_plan_system.md`](docs/domain/attack_plan_system.md), [`docs/domain/vision-system.md`](docs/domain/vision-system.md), [`docs/domain/procgen.md`](docs/domain/procgen.md).

### Autoloads

| Singleton | Purpose |
|---|---|
| `SceneTransition` | Fade in/out + load progress |
| `SceneLoader` | Async scene loading |
| `Events` | Global signal bus (`skill_node_depleted`, …) |
| `StatRegistry` | `StatDef` lookup by `StringName` id |

---

## Design docs (the real source of truth)

The design is much further along than the code. Read in this order:

1. **[`docs/GDD.md`](docs/GDD.md)** — the master GDD. Elevator pitch, core loop, every system in summary, the open questions, the roadmap.
2. **[`docs/design/index.md`](docs/design/index.md)** — index with the recommended reading order across detail docs.
3. **[`docs/design/lore.md`](docs/design/lore.md)** — the world, the Acts, Graph Theology, Tethers, the Fractal, the Fairy.
4. **[`docs/design/combat_system.md`](docs/design/combat_system.md)** + **[`docs/design/combat_worked_examples.md`](docs/design/combat_worked_examples.md)** — the damage pipeline, the //10 spine, three attack modes, and the worked-examples plan for nailing down the defensive function (the single biggest open question).
5. **[`docs/design/stat_system.md`](docs/design/stat_system.md)** — the canonical Stat Vocabulary; the source of truth for stat IDs.
6. **[`docs/design/core_classes.md`](docs/design/core_classes.md)** — Allround, Predator, Bulwark, Ninja, Hive, Halo, Serpent, plus sketched Edgelord/Frontier/Harvester.
7. **[`docs/design/skill_node_addons.md`](docs/design/skill_node_addons.md)**, **[`docs/design/spells.md`](docs/design/spells.md)**, **[`docs/design/metagame.md`](docs/design/metagame.md)** — addons & specializations, the spell catalogue, the hub.

---

## Project conventions

- `@tool` scripts (`SkillNode`, `Entity`, `Graph`) run in the editor. Be careful: opening the editor can round-trip scenes/`.tres` — `git diff` after a refresh is mandatory (see `.claude/rules/godot-workflow.md`).
- Scene access uses unique names: `%PlayerInputController`, `%VisionSystem`, etc.
- `call_deferred` / `await` for post-`_ready` initialization.
- Issue tracking is GitHub Issues (`Koaieus/skill-tree-of-life`); labels include `core`, `design`.

---

## Status & contributing

This is a personal R&D project in active design phase. Code is exploratory; expect breaking changes. Issues and design discussion welcome via the GitHub tracker — but balance, scope, and many systems are deliberately unsettled.

The fastest way to understand the project is to read [`docs/GDD.md`](docs/GDD.md) front-to-back, then poke around the sandbox scenes.
