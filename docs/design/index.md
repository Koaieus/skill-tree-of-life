# Skill Tree of Life — Design Docs

A Godot 4.7 game where the skill tree *is* the game. Entities live on a graph of skill nodes, allocate territory, and fight turn-based battles for dominance. The skill tree is not a UI — it is the world.

> **Roguelite PvP Skill Trees coming to life: The Skill Tree of Life.** You open a game's skill tree, get trapped inside it, and discover other hostile entities occupy nodes on the same tree. Allocate wisely, weaponize the topology, destroy all that opposes you.

The high-level **[GDD](../GDD.md)** is the entry point — vision, core loop, and a map into the per-system docs below.

> 📍 **This folder is what *could* be.** What *is* lives in `docs/domain/` and in code — the spell and core-class rosters are `attack/spell/defs/` and `entity/core/core_class_roster.tres`, and a design doc naming something absent there is describing an idea. What *was* decided lives in [`docs/adr/`](../adr/index.md), including the pre-ADR D-1…D-34 log. Design docs carry no history: within a live doc, a passage the code or a later call has overtaken is deleted, not annotated; a doc that is wholly *built* is archived to [`archive/`](archive/README.md), not deleted.

## Documents

Status is each doc's `status:` frontmatter — `exploring` → `settling` → `built`; a built doc names its `docs/domain/` twin and is then archived to [`archive/`](archive/README.md). See [`../domain/design-doc-lifecycle.md`](../domain/design-doc-lifecycle.md).

| File | Status | What it covers |
|---|---|---|
| [../ROADMAP.md](../ROADMAP.md) | — | **Roadmap** — done / in-progress / todo across all milestones |
| [../GDD.md](../GDD.md) | — | **Master GDD** — pitch, core loop, the supergraph, entities, combat summary, classes, progression, open questions, roadmap |
| [lore.md](lore.md) | `exploring` | Narrative, acts, the Fairy, graph theology, the Field/Tethers/Breakout, the Fractal, tone, visual language |
| [first_session_walkthrough.md](first_session_walkthrough.md) | `exploring` | Spoiler-free, second-person walkthrough of a player's first session — boot screen → first cut-vertex snipe and dismemberment. Funny/Questionable beats called out |
| [combat_system.md](combat_system.md) | `exploring` | Damage pipeline (//10 spine), six-color triangle, ranged/magic/melee (phantom blade), degree → offense, self-loops, single-phase turn (intent by input channel), islands, Breakout, loot/proliferation |
| [click_grammar.md](click_grammar.md) | `exploring` | Open threads on the click grammar — moving core-move onto the generic pop, replacing idle right-click pin/unpin. The shipped grammar is [`../domain/click-grammar.md`](../domain/click-grammar.md) |
| [core_classes.md](core_classes.md) | `exploring` | Core-class design intent. **Shipped:** Balanced, Ninja, Serpent, Pacifist, Wise Cheater (roster: `entity/core/core_class_roster.tres`). Halo has an issue (#786); Allround, Predator, Bulwark, Hive, Frontier, Harvester are ideas only |
| [metagame.md](metagame.md) | `exploring` | Hub between runs, meta skill tree, commit-on-completion, The Way Out |
| [skill_node_addons.md](skill_node_addons.md) | `settling` | Node addons (Armor Ring, Buffer, Gate, Relay, Anti-Magic, etc.), Tech Seeds |
| [skill_node_specializations.md](skill_node_specializations.md) | `exploring` | Node specializations (Corrupted, Crystallized, Anchor) — **early spitball, nothing built or scheduled**; inspiration only |
| [node_subtypes.md](node_subtypes.md) | `exploring` | Node subtypes — open threads only (clustered placement, territory conversion, more families). Shipped model: [`../domain/node-subtypes.md`](../domain/node-subtypes.md) |
| [aspect_matrix.md](aspect_matrix.md) | `settling` | **The Matrix** — every status/concept × ranged/melee/magic, living home of the concept-to-delivery table (#1199) |
| [aspect_personas.md](aspect_personas.md) | `exploring` | **Aspect Personas** — each aspect as a lesser god with a character (Ivy, Cuss, …); lore, parked; built on the matrix's rows |
| [spells.md](spells.md) | `exploring` | Spell identities for the 13 shipped spells (roster: `attack/spell/defs/`), the issue-backed ones, and a fenced idea pool of spells that do **not** exist |
| [damage_over_time.md](damage_over_time.md) | `exploring` | The DoT family's unbuilt half — cures, per-type content, contagion, the defensive-axis matrix. The shipped model is `../domain/effect-system.md` § Status effects |
| [status-tags.md](status-tags.md) | `exploring` | Status tags as a second grant channel — the shipped channel lives in `../domain/effect-system.md`; what remains here is the LifeLine grace-period design (#240) |
| [info_gating.md](info_gating.md) | `exploring` | Info-gating dimensions (existence/archetype/owner/modifiers/addons/…) — why vision is a vector not a boolean, and how sensor/recon/anti-recon mechanics share one surface |

## Reading order

New to the project? `lore.md` for world and story context → `combat_system.md` for mechanics → others as needed. Want to feel what a new player feels? `first_session_walkthrough.md` is spoiler-free and ends at the first dismemberment snipe.

## Engineering docs (`docs/domain/`)

Implementation companions to the design docs — read when modifying systems, not when designing them.

| File | What it covers |
|---|---|
| [../adr/index.md](../adr/index.md) | **Architecture Decision Records** — why we chose this over that, dated and immutable. Read the relevant record before re-arguing a settled call; its rejected-alternatives section marks which grounds are already dead |
| [../architecture.md](../architecture.md) | **The layer map** — which top-level module may depend on which, the allowed direction, today's exceptions; the data lives in `mise run lint-module-deps`, which `check` runs |
| [../reviews/](../reviews/) | **Architecture reviews** — dated, top-down structural assessments with verified citations and the issues they filed; the newest is the current read on layering, composition and debt |
| [../domain/adr.md](../domain/adr.md) | The ADR convention — the boundary against domain docs, the template, how to supersede |
| [../domain/allocation_system.md](../domain/allocation_system.md) | The 3 side-effects, gated vs forced paths, when to use `force_allocate` |
| [../domain/attack_plan_system.md](../domain/attack_plan_system.md) | Attack planner architecture, ranged/melee/magic, VFX, cascade |
| [../domain/melee-blade-sim.md](../domain/melee-blade-sim.md) | Phantom blade PBD physics, deterministic resolve, ghost preview |
| [../domain/node-hp.md](../domain/node-hp.md) | Why per-node HP is a plain field, not a stat; promotion path |
| [../domain/procgen.md](../domain/procgen.md) | Generation pipeline, config knobs, starter group convention |
| [../domain/vision-system.md](../domain/vision-system.md) | Fog of war, Euclidean/sensor visibility, shader, animation |
| [../domain/click-grammar.md](../domain/click-grammar.md) | Shipped left/right click grammar for targeting and allocation |
| [../domain/node-subtypes.md](../domain/node-subtypes.md) | Shipped subtype model — sidegrade law, authoring rows, the decision-number legend |
| [../domain/effect-system.md](../domain/effect-system.md) | Effects, the tag grant channel, and the DoT model (§ Status effects) |
| [../domain/defense-axes.md](../domain/defense-axes.md) | The six defensive axes, their code owners, and the DoT family that answers each (ADR 0022) |
| [../domain/aspect-cell-authoring.md](../domain/aspect-cell-authoring.md) | What each aspect-matrix column actually touches |
| [../domain/stat-knobs-and-bins.md](../domain/stat-knobs-and-bins.md) | House answers for tuning rates, extra pools and forced stat values |
| [../domain/stat-board-classes.md](../domain/stat-board-classes.md) | The StatBoard classes and how they compose |
| [../domain/loot-system.md](../domain/loot-system.md) | Killing-blow XP, tempo and relics |
| [../domain/victory-system.md](../domain/victory-system.md) | The sole emitter of `run_ended`; conditions are swappable |

## Open questions

Each doc tracks its own open questions at the bottom; deeper investigations and tracked work live in **GitHub Issues** (`Koaieus/skill-tree-of-life`, labels `design` / `core`). Keeping per-doc questions near the content they relate to makes them more actionable.
