---
id: 0019
title: Ranged ammo is the entity-board `arrows` PoolStat (the Quiver) with per-type bins, not per-node stock
status: accepted
date: 2026-09-18
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#496"
  - "#495"
  - "#497"
  - "#954"
tags: [ranged, combat, stats, architecture]
---

# ADR 0019 — Ranged ammo is the entity-board `arrows` PoolStat (the Quiver) with per-type bins, not per-node stock

> **Accepted 2026-09-18** by the owner in the #496 swarmify (the "Hub decisions" comment there is the ledger). Proposed earlier the same day off a *"cautious, not definitive"* pick; the swarmify settled the shape below and closed the spatial-reload fork.

## Context

#496 replaces ranged's 1-AP-per-volley economy with limited ammo and AP-cost
reloads. Its body (filed 2026-08) sketched ammo as a **per-node `PoolStat`** on
each firing leaf, with reload refilling one leaf, a group, or leaves within N
hops of the core, and `get_reaching_firing_positions()` becoming a resource
query. Two facts established in the 2026-09-18 design session made that shape
lose:

- **Leaves are churn.** Owner: *"entities often deallocate ~3 nodes per turn
  (or more) and allocate 2 + whatever they deallocated, i.e. creating leaf nodes
  on the fly near where you are going as an Entity is a common practice, leaving
  some nodes permanently allocated (esp far away from any front/enemy) is not."*
  A stock that lives on the node is therefore always on the wrong node: the
  fresh leaf at the front is empty, the stale one in the rear is full.
- **Ranged's identity is one node × many weak hits** (owner, same day), so a
  volley needs 10+ arrows, and any model in which one leaf can unload the whole
  stock ("1 leaf fires all 20 — sounds broken") kills the topological play that
  leaves-as-firing-ports exists for.

Magic already solved the analogous problem: spells live on the entity's
`SpellBook`, ref-counted per granting node, and the magic command-tray body is a
view of that book.

## Decision

Ranged ammo is **one entity-board `PoolStat`, id `arrows`, whose class is
`Quiver`** — current = total stock, max = quiver capacity (`on_cap_rise = PIN`,
so a capacity modifier never gifts arrows), and per-`AmmoType` bins *inside*
current behind `stock_of / add / take`, the `SkillPointStat` precedent. The
class IS the stat: there is no separate Quiver resource on `Entity`, and the
ranged command-tray body is a view of `stat_board.arrows` as the magic body is
a view of `SpellBook` (#954). Owner, 2026-09-18: *"One and the same: `Quiver
extends PoolStat`, stat id `arrows`."*

Stock is fed by `ReloadCommand` (1 AP): Σ over the leaves the entity held at
its **turn start** ∪ core of the node-local `arrows_per_reload`, plus each
special type's flat `<type>_arrows_per_reload`; nodes *grant* those minting
stats as ordinary entity-board modifiers (#497). Owner: *"'+1 poison arrows'
stat + modifiers (the 'per reload' might best be left implied); … nodes would
`grant` those modifiers."*

Topology enters through a **per-leaf shot budget that is node runtime state,
not a board stat**: `SkillNode.shots_fired_this_turn`, with
`shots_left = local max_shots_per_leaf − fired` (owner, 2026-09-18), reset at
the firer's turn end over the exact set of nodes it fired from — never a sweep,
never a node-board pool (a pool's cap is fed by the owner's board and would
clamp to 0 on deallocation, losing the deficit the owner wants preserved).
Both counters are reproduced by mirrors from the command stream.

## Consequences

- Stock and bins ride `Quiver.to_dict` through the ordinary board snapshot; the
  wire carries reloads as commands and a volley's `ammo_counts` on the plan —
  no per-node pool to snapshot (ADR 0020).
- `Quiver` is authored on `EntityStatBoard` + `default_entity_board.tres`,
  never minted through `StatBoard._mint_stat` (which mints a plain `PoolStat`).
- A leaf with no shots left is a third firing-position state the plan's
  `validate()` must know (#957).
- Spatial reload ("leaves within N hops of the core") is **closed out of the
  hub** — owner 2026-09-18: all leaves, counted at turn start. It survives as a
  sibling (#961) that filters the same turn-start set.
- The tray mockup's per-leaf ammo assignment and ordered bands (#954) are not
  this shape; composition is typed counts in a fixed roster order.

## Alternatives considered

### Per-node `PoolStat` ammo (the #496 body)
Makes each leaf individually meaningful and reload a spatial act. Lost to leaf
churn: the arrows are never where the front is, and a player who keeps leaves
only to hold their ammo is playing against the game's own allocation rhythm.
The spatial-reload idea it carried survives independently (see Consequences).

### Fletcher logistics (production nodes ship arrows to the core, core to leaves)
Owner: *"could be fun but also it's way out there, and i think simpler / more
elegant solutions might work out better."* Parked, not rejected on grounds.

### Entity stock with no per-leaf cap
Simplest, and broken: one leaf in range fires everything; topology stops
mattering. Rejected on the identity, not on cost.

### A separate `Quiver` resource on `Entity` reading/writing an `arrows` pool
SpellBook-shaped. Two homes for one fact (bins vs total) that must be kept in
sync — rejected 2026-09-18 for the stat-with-bins shape.

### Per-leaf budget as a node-board `PoolStat` (`shots`, REFILL per turn)
Owner's first pick the same evening, withdrawn on the readout: the cap comes
from the owner's board via the localized read, so deallocation clamps current
to 0 and re-allocation refills it — the same-turn deficit cannot survive
without a second, entity-held record. A runtime counter is one fact, one home.
