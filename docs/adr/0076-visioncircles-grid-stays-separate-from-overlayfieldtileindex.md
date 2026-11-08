---
id: 0076
title: VisionCircles' spatial grid stays separate from OverlayFieldTileIndex
status: accepted
date: 2026-08-17
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "one of the two grids needs a structural rework anyway — re-check whether the four parameter differences still hold"
sources:
  - "docs/domain/vision-system.md"
  - "docs/domain/overlay-field-rendering.md"
  - "systems/vision_circles.gd"
tags: [vision, fog, performance, architecture]
---

# ADR 0076 — VisionCircles' spatial grid stays separate from OverlayFieldTileIndex

Backfill, recorded 2026-11-08: the decision lived in `vision-system.md` prose
(and a code comment before that) since it was made.

## Context
`VisionCircles` (gameplay vision queries) and `OverlayFieldTileIndex` (the fog
overlay's tile index) each build a uniform grid over what looks like the same
set of circles. The resemblance invites a shared substrate, and ADR 0068 later
rejected reusing `VisionCircles` as the reach grid "for the same reasoning" —
citing this decision without a record to cite.

## Decision drivers
- Exactness: vision answers a hard boolean; a wrong cell class is a wrong answer.
- The overlay's CPU walk must match its fragment shader's tile-gather exactly,
  including a hand-tuned epsilon with 0.0013 headroom.
- Code saved by merging must outweigh the parameterisation it forces.

## Decision
The two grids are not merged — investigated and rejected 2026-08-17. Each class
owns its own index.

## Consequences
Buys: each grid keeps the exact cell size, margin, storage and semantics its
consumer needs; the overlay's fragile epsilon is untouched by vision changes.
Costs: two uniform-grid implementations exist and the resemblance must be
re-explained — this record is that explanation.

## Alternatives considered
### One shared grid substrate under both
Lost on every driver: the grids differ in cell size (`max_radius` vs
`(1 + union_smoothness) × max_radius`), margins (1× max_radius vs 2× cell_size
plus a measured `1e-4 × cell_size` epsilon fixing a CPU/shader darkness
mismatch), storage (dense flat Array vs sparse Dictionary that serialises
row-major into GPU data textures) and semantics (hard boolean union vs soft
field fold matching the shader's gather order). A shared substrate would need a
parameter for each and risk the epsilon, for ~15–20 lines of superficial shape.
Most likely to be revived if either grid is structurally reworked.
