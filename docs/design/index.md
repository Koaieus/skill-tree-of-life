# Skill Tree of Life — Design Docs

A Godot 4.4 game where the skill tree *is* the game. Entities live on a graph of skill nodes, allocate territory, and fight turn-based battles for dominance. The skill tree is not a UI — it is the world.

> **Roguelite PvP Skill Trees coming to life: The Skill Tree of Life.** You open a game's skill tree, get trapped inside it, and discover other hostile entities occupy nodes on the same tree. Allocate wisely, weaponize the topology, destroy all that opposes you.

The high-level **[GDD](../GDD.md)** is the entry point — vision, core loop, and a map into the per-system docs below.

> 📍 **For MVP-current state on contested questions, read [mvp_decisions.md](mvp_decisions.md) first** — it supersedes older sketches in the per-system docs where they disagree. Also see [../ROADMAP.md](../ROADMAP.md) for what's done vs in-flight.

## Documents

| File | What it covers |
|---|---|
| [mvp_decisions.md](mvp_decisions.md) | **MVP decisions log** — authoritative current state for the 8 D-decisions (melee model, cast range, addons, factions, etc.). Supersedes per-system sketches where they disagree |
| [../ROADMAP.md](../ROADMAP.md) | **Roadmap** — done / in-progress / todo across all milestones |
| [../GDD.md](../GDD.md) | **Master GDD** — pitch, core loop, the supergraph, entities, combat summary, classes, progression, open questions, roadmap |
| [lore.md](lore.md) | Narrative, acts, the Fairy, graph theology, the Field/Tethers/Breakout, the Fractal, tone, visual language |
| [first_session_walkthrough.md](first_session_walkthrough.md) | Spoiler-free, second-person walkthrough of a player's first session — boot screen → first cut-vertex snipe and dismemberment. Funny/Questionable beats called out |
| [combat_system.md](combat_system.md) | Damage pipeline (//10 spine), six-color triangle, ranged/magic/melee (phantom blade), degree → offense, self-loops, single-phase turn (intent by input channel), islands, Breakout, loot/proliferation |
| [combat_worked_examples.md](combat_worked_examples.md) | 3 worked fights in real numbers; the tempo axiom; the defense-function decision (battle-formula handoff doc) |
| [core_classes.md](core_classes.md) | All entity core classes: Allround, Predator, Bulwark, Ninja, Hive, Halo, Serpent, Frontier, Harvester |
| [stat_system.md](stat_system.md) | Stat architecture (v2 direction), modifier pipeline, canonical stat vocabulary |
| [entity_stat_board_prototype.md](entity_stat_board_prototype.md) | Prototype stat values, SP accounting model, damage formula, class stat variations |
| [metagame.md](metagame.md) | Hub between runs, meta skill tree, commit-on-completion, The Way Out |
| [skill_node_addons.md](skill_node_addons.md) | Node addons (Armor Ring, Buffer, Gate, Relay, Anti-Magic, etc.), Tech Seeds |
| [skill_node_specializations.md](skill_node_specializations.md) | Node specializations (Corrupted, Crystallized, Anchor) |
| [spells.md](spells.md) | Spell catalogue — identity and propagation mechanics for all Blue (INT/magic) spells |
| [info_gating.md](info_gating.md) | Info-gating dimensions (existence/archetype/owner/modifiers/addons/…) — why vision is a vector not a boolean, and how sensor/recon/anti-recon mechanics share one surface |

## Reading order

New to the project? `lore.md` for world and story context → `combat_system.md` for mechanics → others as needed. Want to feel what a new player feels? `first_session_walkthrough.md` is spoiler-free and ends at the first dismemberment snipe.

## Engineering docs (`docs/domain/`)

Implementation companions to the design docs — read when modifying systems, not when designing them.

| File | What it covers |
|---|---|
| [../domain/allocation_system.md](../domain/allocation_system.md) | The 3 side-effects, gated vs forced paths, when to use `force_allocate` |
| [../domain/attack_plan_system.md](../domain/attack_plan_system.md) | Attack planner architecture, ranged/melee/magic, VFX, cascade |
| [../domain/melee-blade-sim.md](../domain/melee-blade-sim.md) | Phantom blade PBD physics, deterministic resolve, ghost preview |
| [../domain/node-hp.md](../domain/node-hp.md) | Why per-node HP is a plain field, not a stat; promotion path |
| [../domain/procgen.md](../domain/procgen.md) | Generation pipeline, config knobs, starter group convention |
| [../domain/vision-system.md](../domain/vision-system.md) | Fog of war, Euclidean/sensor visibility, shader, animation |

## Open questions

Each doc tracks its own open questions at the bottom; deeper investigations and tracked work live in **GitHub Issues** (`Koaieus/skill-tree-of-life`, labels `design` / `core`). Keeping per-doc questions near the content they relate to makes them more actionable.
