---
id: 0064
title: The inner (aspect) ring is a hand-authored Graph scene of the board's own SkillNodes and Edges, and a cell is buyable iff an edge links it to the centre Core or a bought cell — the edges are the rules
status: accepted
date: 2026-10-17
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "a ring rule cannot be expressed as topology plus a cell addon (the AND-gate is the likeliest), or a second ring needs procgen rather than authoring"
sources:
  - "#1651"
  - "#1652"
  - "#1663"
  - "#1669"
  - "docs/design/inner_ring_ui.md"
  - "docs/design/inner_tree_and_stake_economy.md"
  - "graph/graph.tscn"
tags: [entity, ring, aspects, graph, authoring, architecture]
---

# ADR 0064 — The inner ring is an authored Graph scene; its edges are its buy rules

## Context
#1651 specced the per-entity aspect ring (6 sectors × T1/T2/keystone cells bought with a milestone-minted ring point) as data: a `RingDef` resource of `RingCell`s carrying `requires_all` / `requires_any` lists, with the UI (#1652) left to lay it out. It was unbuilt. Designing the surface, the owner asked for it to read like a PoE passive tree, not a simple ring, and to grow by authoring. That raised the question of what the ring is in code. The board already has an authored-graph path (`graph.tscn`, SkillNodes, Edges, keystone scenes, `SkillNodeAddon`s), as `dev_sandbox.tscn` shows.

## Decision drivers
- One node and edge implementation. The ring should not grow a second one that drifts from the board's.
- Authorable in the editor: layout, keystone position and cell content composed by hand, and later swappable (for example, keystones per core class).
- Rules live in one place. Buyability is not kept as a list beside the topology it describes, and it is not a second notion of adjacency beside the board's.
- Headless and host-authoritative. Spending is a command; the entity stores only what it bought.

## Decision
Owner, 2026-10-17: *"this would not be a procgen unit, but a hand authored scene with nodes and edges and node content readily composed. (and keystone position too; can later be swapped out for others e.g. coreclass specific keystones if we so want)"*

Owner, 2026-10-17, from scored options: the ring is **"An authored Graph scene"**, and buyable cells follow **"PoE adjacency"**, which the owner then glossed: *"\"PoE adjacency\" is also just .. our own adjacency of our conventional graph playing field"*.

Owner, 2026-10-17: *"Graph but visuals and background and core visuals differ, core cant move etc, dealloc pts for those is a separate resource"*

`entity/ring/aspect_ring.tscn` instances `graph/graph.tscn`. Its cells are SkillNodes, and its keystones are `keystone_skill_node.tscn` instances. Each non-core cell carries a `RingCellAddon` holding the aspect, sector, tier, cost and the grant in `entity_modifiers`. A cell is buyable iff it is unspent, affordable, and an authored edge links it to the centre `Core` or to a cell this entity bought. That is the board's own allocation adjacency, read off the same `Graph` neighbours, rather than a ring-specific rule.

## Consequences
- Growing or reshaping the ring is a scene edit. Adding a cell or a link takes no code change.
- The entity stores `ring_spent: Array[StringName]`. A cell is identified by its node `name`, never by `stable_id`, which mints lazily per Graph instance while the scene is instanced more than once.
- A system loads the scene once and reads a rules table from it. Ring spends never go through `AllocationSystem`. The centre `Core` is inert: it is the root of adjacency and is never bought or moved.
- Refunds draw on a pool of their own, never the board's `deallocation_points`.
- The view reuses the board's node and edge visuals but needs its own background and core visual.
- Cost: every gate the ring needs must be topology or a cell addon. A rule that spans cells has no home outside the scene.

## Alternatives considered

### Bespoke RingCell / RingLink nodes
Lost on *one implementation*: it is a second node+edge stack that drifts from the board's. Its only ground was a lighter, purpose-built type, and the board's SkillNode already carries everything a cell needs through an addon.

### Keep #1651's `RingDef` resource; the UI lays it out
Lost on *authorable*: it contradicts "hand authored scene … keystone position too". It also keeps the rules as lists beside a layout computed elsewhere. That ground is dead while the ring is authored rather than generated.

### Adjacency plus AND-gates (`requires_all`) now
Lost on *rules in one place*: it puts rules beside the topology. **Most likely to be revived.** A "T2 needs a neighbouring T1 too" gate may return as an optional gate addon on a cell, which keeps it in the scene.
