# Skill Tree of Life — Design Docs

A Godot 4.4 game where the skill tree *is* the game. Entities live on a graph of skill nodes, allocate territory, and fight turn-based battles for dominance. The skill tree is not a UI — it is the world.

## Documents

| File | What it covers |
|---|---|
| [lore.md](lore.md) | Narrative, acts, the Fairy, graph theology, the Field/Tethers/Breakout, the Fractal, tone, visual language |
| [combat_system.md](combat_system.md) | Damage pipeline, RGBW triangle, ranged/magic/melee rules, degree → defense, self-loops, islands, Breakout, loot resolution |
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
