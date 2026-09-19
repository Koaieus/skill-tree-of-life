---
id: 0021
title: Ranged reach is an isotropic disc and a volley targets a node set — no lanes, cover, or hull geometry
status: accepted
date: 2026-09-18
deciders: owner+agent
supersedes: []
superseded-by: null
sources:
  - "#496"
  - "#11"
  - "test/perf/bench_ranged_geometry.gd"
  - "attack/range_finder/euclidean_range_finder.gd"
tags: [ranged, combat, procgen, architecture]
---

# ADR 0021 — Ranged reach is an isotropic disc and a volley targets a node set — no lanes, cover, or hull geometry

## Context

The 2026-09-17/18 design sessions on "what is ranged's blade?" produced a family
of *geometric* proposals from two Fable sparring agents: a leaf fires along its
stem edge and can bend ±`aim_arc` ("fire lanes"); an arrow hits the first body
on its segment ("cover / line of fire"); a target inside the firing hull takes
armour once per volley ("enfilade"); a focus radius in px around a clicked
point; and focus-as-accuracy (gaussian landing, hit whatever is underneath).
Each would have added a range-finder or a landing predicate that reads
positions as *directions* or *obstacles* rather than as distances.

Two measurements on the shipped `first_level` preset (5 seeds × 800 nodes,
`test/perf/bench_ranged_geometry.gd`, commit 771b291) settled it:

- **Lanes choice metric.** Walking toward a rival, at each frontier step the
  number of allocatable neighbours whose stem would point within 45° of the
  rival has **median 1, mean 0.9; 23 % of steps have zero, 11 % have ≥ 2.**
  Allocation is not aiming on this procgen; a stem-direction gate is luck. The
  agent that proposed it set the gate itself: *"if the median is 0–1 the player
  never had a decision and lanes are luck … lanes should die rather than ship
  soft."*
- **Spacing.** Poisson-disk spacing gives a minimum centre-to-centre distance
  of **150 px** (median edge 174 px, node radius median 35 px). A 40 or 80 px
  disc around a node touches no other node; 160 px touches a median of 2.

## Decision

Ranged reach stays what `EuclideanRangeFinder` computes: an **isotropic disc**
per leaf, radius = the leaf's node-local `range`. A volley's targets are a
**set of nodes** chosen by the player (today one; #496 may add a count), never
a region, a ray, a cone, or a hull. Nothing between a firing leaf and its
target blocks, deflects, or discounts an arrow. No `ConeRangeFinder`, no
segment-vs-hitbox test, no hull predicate is built.

The one geometric idea kept warm, by the owner (2026-09-18): *"leaf-stem
direction is indeed to be kept warm because it plays into a truly topological
property of the graph, the direction an edge goes (acting as a directed edge
even)."* If it returns, it returns as **range scaling with alignment** (a dot
product on the stem), never as a damage modifier and never as a hard gate — and
only after re-running the choice metric.

## Consequences

- Reach, targeting and the AI's candidate gathering stay pure
  distance-plus-ownership queries; the tray can preview a volley without a
  physics pass.
- Topology enters ranged through **which leaves exist and where** (firing
  ports, per-leaf caps — ADR 0019), not through edge bearings.
- Any future "focus" or "spread" knob is counted in **nodes or hops**, not px
  (the 0–100 px band is a dead zone that looks like a knob).
- The grounds are empirical: a procgen change that spaces nodes tighter or
  makes stems fan toward rivals should re-run the bench before anyone
  re-argues this.

## Alternatives considered

### Fire lanes (`aim_arc`, hard gate or soft half-damage)
Lost on the choice metric above. The soft variant lost separately: at the
base-10 anchor an arrow is 1–2 damage, so ×0.5 *"is either nothing or
everything after rounding"*, and a flat penalty on wrong-facing stubs *"is a
constant background penalty nobody decides about"*. Grounds: measured (live),
and the damage-rounding argument (live).

### Cover / line of fire, and enfilade (armour once per volley inside the hull)
Rejected as illegible at a few hundred nodes: *"a hull is the illegible
primitive, and it's a 2-10× damage swing on a geometric predicate the player
can't read at a glance."* Cover also surfaced that `combat_system.md` says
armour applies once per volley while the code applies it per arrow
(`Mitigation.apply` per `RangedHitInstance`) — the doc line is the stale one.
Grounds: legibility (live).

### Focus radius in px
Dead zone below ~120 px on the measured spacing; if a focus knob ships it is
counted in nodes/hops. Grounds: measured (live).

### Focus as accuracy (gaussian landing point, hit what is underneath)
At node r ≈ 35 px inside a 160 px disc the hit rate is ~5 %; illegible, and a
second RNG stream on the landing point is a desync source under
host-authoritative replay. Grounds: measured + sync (live).
