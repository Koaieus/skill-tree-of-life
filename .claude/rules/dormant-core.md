---
description: Dormant Core (aka blocker) — player-facing name, loot tiers, and the seeded spell-book prune
paths:
  - "entity/blocker/**"
  - "entity/spell_book.gd"
  - "skill_node/blocker_node.tscn"
  - "skill_node/visuals/blocker_visual.gd"
  - "procgen/graph_procgen.gd"
  - "procgen/graph_procgen_config.gd"
  - "scenes/game_root.gd"
---

A **Dormant Core** is a single-node entity that holds a node and never moves or
acts. See docs/domain/dormant-core.md for tiers, loot books, and the prune math.

**Player-facing text says "Dormant Core"; code says `blocker`.** Every
identifier — `BlockerSize`, `spawn_blocker`, `blocker.tres`, `blocker_per_*` —
keeps `blocker` on purpose. Renaming an `@export` var would make Godot drop the
old key from saved `GraphProcgenConfig` resources and silently fall back to the
default, quietly changing level generation.

**Why:** `blocker` names the mechanic well and the thing badly.

**How to apply:** when you add a surface a player reads, use `display_name`, not
the node `name` (the node name carries Godot's `@2` uniquifier). Don't "fix" a
`blocker` identifier you see in code.

**The prune knob only goes down.** `GraphProcgenConfig.blocker_spell_prune_m` is
the `m` in a `n/(n+m)` pop chain over the tier's loot book; `m == 1` makes every
outcome in `{0..n}` equally likely. Raising `m` keeps MORE spells, so kills offer
nothing less often and spells spread FASTER — the opposite of the knob's purpose.

**Why:** a relic's claimant picks exactly one spell from whatever is offered, so
`P(book is empty)` is the only lever on spell spread; book size is the other half
of it (`1/(n+1)` at `m == 1`).

**How to apply:** the roll is seeded per placement by procgen, because every peer
re-runs the level scene and reproduces it. Never roll it unseeded at spawn.
