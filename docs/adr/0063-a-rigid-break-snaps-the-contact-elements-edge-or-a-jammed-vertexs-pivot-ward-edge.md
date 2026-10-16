---
id: 0063
title: A rigid bunker break snaps the contact element's own edge, or a jammed vertex's live edge toward the pivot — never "the most strained" edge — supersedes 0005's edge pick in part
status: accepted
date: 2026-10-16
deciders: owner (which edge snaps, the pivot-as-only-driver grounds); pass (hop distance over live edges, lowest-index ties)
supersedes: [0005]
superseded-by: null
revisit-when: "A blade gains a second driver besides the pivot, so an element not rigid-connected to the pivot can carry more load than one that is"
sources:
  - "#1633"
  - "#1369"
  - "docs/adr/0005-blade-parts-and-counters-are-orthogonal.md"
  - "docs/domain/melee-blade-sim.md"
tags: [combat, melee, blade, physics]
---

# ADR 0063 — A rigid break snaps the contact element's edge, or a jammed vertex's pivot-ward edge

## Context

ADR 0005 holds: spikes pop vertices, bunkers break edges, a bunker never pops a
vertex. It answered *which* edge fails with the constraint residual, "the most
strained". The shipped meter banked strain onto a pushed vertex's edges by
`|normal · edge_direction|`; the swing-wise normal crosses the radial edge to the
pivot, so that edge banked ~0 and the pick landed on an outer rung.

## Decision drivers

- The pivot is the blade's only driver; load reaches a jammed element through its
  rigid path to the pivot.
- Contact and consequence should read together: the edge that snaps is visibly the
  one the plate is loading.

## Decision

**Owner, 2026-10-16 (#1369):** *"the edge hitting the bunker or the edges of whatever
blade vtx node is hitting the bunker snap (in case of vtx×bunker hit, the edge closest
to pivot snaps first)"* — and *"given the pivot is the only driver … there's no way
anything that is not rigid-connected to the pivot can experience more strain than a
rigid-connected-to-pivot … element being blocked by a bunker"*.

At shatter time the zone picks its contact element (most refused drive, lowest index
on a tie). An edge capsule → that edge breaks. A vertex disc → its live incident edge
toward the pivot (smallest hop distance over live edges, lowest edge index on a tie).
Only 0005's answer to "which edge" is replaced; the rest of 0005 stands.

## Consequences

The break reads at the contact; a jammed grip snaps its own edge to the pivot. Hop
distance is re-derived after a sever (`removed_edges` changes reachability). The
refused-drive trigger (`SHATTER_DISTANCE`) and every "does it break" verdict stand.

## Alternatives considered

**Most strained edge by residual / directional banking** (0005, as shipped). Lost on
the first driver: the projection banks ~0 on exactly the pivot-ward edge the load
runs through, so the pick lands on a rung the plate is not loading. Dead.

**Pop the contacting vertex.** Rejected by 0005; not reopened here.
