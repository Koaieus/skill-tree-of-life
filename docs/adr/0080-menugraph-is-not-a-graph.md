---
id: 0080
title: MenuGraph is menu-local data, not a Graph — the menu borrows node visuals and none of the machinery
status: accepted
date: 2026-08-24
deciders: owner
supersedes: []
superseded-by: null
revisit-when: null
sources:
  - "docs/domain/frontmatter-shell.md"
  - "ui/frontmatter/menu_graph.gd"
tags: [ui, menu, architecture]
---

# ADR 0080 — MenuGraph is not a Graph

Backfill, recorded 2026-11-08: the owner's sentence has lived in
`frontmatter-shell.md` (a code comment before that) since the call.

## Context
The frontmatter menu renders a tree of node-shaped items that look exactly like
gameplay skill nodes, and the gameplay `Graph`/`SkillNode` stack already
existed. Reusing it was the obvious reach; the menu needs none of its
allocation, stats, turns or persistence.

## Decision drivers
- The menu must not drag `Graph`, `SkillNode`, `Entity`, `StatBoard`,
  `AllocationSystem` or `TurnManager` into a screen that has no gameplay.
- The composability bet: visuals should be stealable without their machinery.

## Decision
"special menu local model for sure, if we did our composibility right we could
steal just the *visuals* of the real elements involved iff not using the real
ones directly" — owner, 2026-08-24. `MenuGraph` carries topology and routing
only; the menu instances `node_visuals_composite.tscn` for the look.

## Consequences
Buys: the menu is a plain tree (one parent each, no cycles) with no gameplay
dependencies, and the visuals-without-machinery bet is proven — the composite
renders outside an `Entity`. Costs: topology routing exists twice (menu-local
and live `meta_root.gd`), held together by `test_meta_routing_parity.gd`.

## Alternatives considered
### Reuse Graph/SkillNode directly for the menu
Lost on the first driver: every menu screen would construct and tick gameplay
machinery to draw a static tree, and gameplay refactors would break the menu.
Most likely to be revived if the menu ever needs real allocation semantics.
### A bespoke menu renderer (own visuals)
Lost on the second driver: duplicates the node look and drifts from it; the
whole point of the composite split is that the look is borrowable.
