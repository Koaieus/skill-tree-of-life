# Skill Tree of Life — Design Docs

A Godot 4.4 game where the skill tree *is* the game. Entities live on a graph of skill nodes, allocate territory, and fight turn-based battles for dominance. The skill tree is not a UI — it is the world.

> **Roguelite PvP Skill Trees coming to life: The Skill Tree of Life.** You open a game's skill tree, get trapped inside it, and discover other hostile entities occupy nodes on the same tree. Allocate wisely, weaponize the topology, destroy all that opposes you.

The high-level **[GDD](../GDD.md)** is the entry point — vision, core loop, and a map into the per-system docs below.

## Documents

| File | What it covers |
|---|---|
| [../GDD.md](../GDD.md) | **Master GDD** — pitch, core loop, the supergraph, entities, combat summary, classes, progression, open questions, roadmap |
| [lore.md](lore.md) | Narrative, acts, the Fairy, graph theology, the Field/Tethers/Breakout, the Fractal, tone, visual language |
| [combat_system.md](combat_system.md) | Damage pipeline, RGBW triangle, ranged/magic/melee rules, degree → defense, self-loops, islands, Breakout, loot resolution |
| [combat_worked_examples.md](combat_worked_examples.md) | 3 worked fights in real numbers; the tempo axiom; the defense-function decision (battle-formula handoff doc) |
| [core_classes.md](core_classes.md) | All entity core classes: Allround, Predator, Bulwark, Ninja, Hive, Halo, Serpent, Frontier, Harvester |
| [stat_system.md](stat_system.md) | Stat architecture (v2 direction), modifier pipeline, canonical stat vocabulary |
| [entity_stat_board_prototype.md](entity_stat_board_prototype.md) | Prototype stat values, SP accounting model, damage formula, class stat variations |
| [metagame.md](metagame.md) | Hub between runs, meta skill tree, commit-on-completion, The Way Out |
| [skill_node_addons.md](skill_node_addons.md) | Node addons, node specializations, Tech Seeds |
| [spells.md](spells.md) | Spell catalogue — identity and propagation mechanics for all Blue (INT/magic) spells |

## Reading order

New to the project? `lore.md` for world and story context → `combat_system.md` for mechanics → others as needed.

## Open questions

Each doc tracks its own open questions at the bottom. There is no central list — keeping them near the content they relate to makes them more actionable.
