---
id: 0068
title: Straight-line reach gathers ride a Graph-owned uniform grid of SkillNode centres, filtered by mirror membership — not the physics broadphase, not a grid per mirror
status: accepted
date: 2026-10-19
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "SkillNode positions start moving in play (the broadphase's per-frame sync becomes value, not cost); or a profile shows the one-off grid build (1.1/2.9/4.6 ms at 800/2k/3k nodes) on a hot path; or the AI tier needs gathers off the main thread — a reason FOR the grid, but its rebuild contract must be re-checked"
sources:
  - "#1701"
  - "#945"
  - "#1391"
  - "2810c244403b"
  - "attack/range_finder/euclidean_range_finder.gd"
  - "graph/graph.gd"
  - "graph/graph_mirror.gd"
  - "systems/vision_circles.gd"
tags: [graph, range-finder, spells, performance, determinism, architecture]
---

# ADR 0068 — Straight-line reach gathers ride a Graph-owned uniform grid

## Context

`EuclideanRangeFinder.gather` / `gather_multi` — the one candidate source for spell target unions, splash riders, node targeting and auras — walked every node of the mirror handed in, and that mirror is usually the whole board: 959 / 2469 / 3728 µs per gather at 800 / 2000 / 3000 nodes (probe bench, commit 2810c244403b, 2026-10-19). ADR 0021 fixed the predicate (an isotropic disc, `_reaches`); nothing had decided the candidate source. #945 benched physics `intersect_shape` and closed on 2026-09-20 naming the seam, and the owner's leaning going in, 2026-10-19, was physics: *"I figured it's building our own of what physics already is sharpened to do and does"*. The constraint the owner set in the #1391 pass, 2026-10-19: *"the test: N nodes on an N node map is absolute worst of the worst ... we can't be doing that test on N nodes that's out for sure"* and *"We still need that speedup and we prefer investing in our perf for foreseeable future rather than patching it 10 times, a patch whenever when we add complexity"*. Verified in the pass: no play path writes a SkillNode position (procgen and snapshot load only), and allocation adds or removes no container child.

## Decision drivers

- Structural over patching: one index that every future distance mechanic rides through a per-call-reach entry (Dazzle as a flashbang, `docs/design/aspect_matrix.md` "Blind the overlap"), never a per-mechanic fix.
- Single owner of each fact: Graph owns board geometry, a mirror owns membership, `_reaches` owns the predicate.
- No frame or thread coupling for data that never moves in play.
- Peer-deterministic result order by construction (a procgen'd host and a snapshot-loaded peer).
- Speed was measured and did not discriminate between grid and physics — see Alternatives.

## Decision

Owner, 2026-10-19 (`/swarmify` pass of #1701), choosing from four scored options: **"Grid on Graph (Recommended)"** — reaffirmed with the identical answer the same day after the pass corrected a wrong premise it had given (a claimed ~300 µs physics floor; measured ~15 µs at 250 px) and showed the full axis-by-axis comparison. Owner, 2026-10-20: *"Let subagent ADR it"*. A firm call, made against the owner's own stated leaning with the numbers in view.

`Graph` owns a `SkillNodeGrid` (`graph/skill_node_grid.gd`): a uniform grid of SkillNode *centres* plus one running max radius, beside the lazily rebuilt adjacency cache and dirtied by the same container child hooks; each node's `radius_changed` raises the max radius so the `reach + max_radius` margin stays exact as stake grows. `gather` / `gather_multi` route through one reach-explicit entry that takes the board's candidates and keeps those with `mirror.vertex_id(n) >= 0` — owned mirrors and shadow-world mirrors are covered by the one index. `_reaches` stays the one predicate and the index only narrows candidates, so a stale index can only miss, never admit. Buckets bin in `stable_id` order. The linear scan survives only as the fallback for a graph-less fixture mirror.

## Consequences

- Buys: 14–16 µs at 250 px and 253–293 µs at 1500 px on every board measured (scan: 959–3778); no rebuild in play; no physics-frame await in a spawn-and-gather fixture; plain arrays readable from a worker thread while nothing rebuilds; an identical bucket walk on every peer.
- Costs: a one-off build (1.1 / 2.9 / 4.6 ms) on the first query after a container change; a position write after that query is unseen until the next container change — the clause `graph.md` already carries for re-pointing a live `Edge`; `gather_multi`'s shared-sweep rationale is gone, it is one small query per source.

## Alternatives considered

### Physics `PhysicsDirectSpaceState2D.intersect_shape` with a `CircleShape2D(reach)` — most likely to be revived
Benched in #945 and again in this pass. **Speed is not the ground**: physics measured 15 / 19 / 19 µs at 250 px and 384 / 454 / 502 µs at 1500 px — a tie at short reach, slower at long; an agent re-running the bench and finding physics fast has learned nothing new. Lost on *no frame or thread coupling*: positions never move in play, so the broadphase's per-frame sync is cost the data never needs; a same-frame spawn is missed for one physics frame, so every same-frame spawn-and-gather fixture needs a physics-frame await; main thread only (ADR 0014 already had to build-then-consume around that rule for the blade solver); undefined result order needing a `stable_id` sort per result for peer determinism; `GAMEPLAY_QUERY_MASK` and `max_results` discipline. Revives if nodes start moving — the `revisit-when`.

### A grid per `GraphMirror` (dirtied by `mirror_add` / `mirror_remove`)
Lost on *single owner*: N copies of one geometric fact, every entity's grid rebuilt on every allocation where the Graph-owned grid never rebuilds in play, radius tracking duplicated per mirror, geometry owned by the membership object.

### Hybrid — physics for melee splash riders, grid elsewhere
Two candidate sources for one predicate, both sets of caveats; melee riders already gather on the global navigator, so the split buys nothing.

### Reuse `VisionCircles` (`systems/vision_circles.gd`) as the grid
Its cell is the max radius (~32 px), which at 1500 px walks thousands of empty cells; it is rebuilt per `VisionSystem._recompute`; it answers point-in-union, not disc-overlaps-circle — the same reasoning as its own don't-merge note about `OverlayFieldTileIndex`.
