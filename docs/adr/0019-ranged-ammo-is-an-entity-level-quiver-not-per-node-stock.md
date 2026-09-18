---
id: 0019
title: Ranged ammo is an entity-level Quiver shaped like SpellBook, not per-node stock
status: proposed
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

# ADR 0019 — Ranged ammo is an entity-level Quiver shaped like SpellBook, not per-node stock

> **Proposed**, not accepted: the owner's pick on #496 (2026-09-18) is explicitly
> *"cautious, not definitive"*. This ADR exists to frame the fork so the
> `/swarmify` of #496 accepts or rejects it rather than re-deriving it — the
> #496 body itself still describes the per-node alternative.

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

Ranged ammo is a **per-entity Quiver**: stock per ammo type on the entity, fed
by reload and by `+N <type> arrows` modifiers that nodes *grant* (#497) — the
granting node need not be a leaf, and its arrows do not vanish when the node is
deallocated mid-turn any more than a `SpellBook` entry does. Topology enters
through a **per-leaf cap on shots per turn** (a transient counter on the leaf,
reset at the owner's turn start, scaled by `allocation_level` and by
`WatchtowerAddon`), never through where the arrows are stored. The ranged
command-tray body is the Quiver's view, as the magic body is the SpellBook's
(#954).

Owner, 2026-09-18: *"'+1 poison arrows' stat + modifiers (the 'per reload' might
best be left implied); Ranged CommandTrayBody could show all owned ammo types
(current + amount gained on reload; shown so long either >0) and reload options
and whatnot, basically a representation of Quiver much like the Magic
CommandTrayBody is a representation of SpellBook. nodes would `grant` those
modifiers."*

## Consequences

- Stock is one entity-level quantity per ammo type; the wire carries it through
  the reload command and the volley's `N` — no per-node pool to snapshot.
- The per-leaf cap is per-turn runtime state derived from commands, so it must
  be reproduced by mirrors from the command stream, never snapshotted; a leaf
  with 0 shots left is a third firing-position state the plan's
  `validate()` does not know today.
- Reload can still be made spatial ("leaves within N hops of the core count
  toward the reload") without moving the stock — the fork stays open on #496.
- The tray mockup's per-leaf ammo assignment (#954) is *not* this shape; if
  ordered bands ship they are quiver order, re-derived per target.

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
