# Handoff — FogOverlay per-element dimming (lane P's framerate collapse)

**Written against `118b5cf`, 2026-08-18.**

Authoritative homes, in this order: **#414** (owns the fix), **#439** (owns the
aura half), `docs/FOCUS.md` lane P (why it outranks everything),
`test/perf/bench_fog_refresh_cost.gd` (the numbers and how to reproduce them).
This file is an index and a sequencing note. It holds nothing of its own.

## What is settled

`FogOverlay._apply_per_element_dimming` **is** the sustained framerate drop
reported from playtesting. Not the shader, not the vision recompute, not the
allocation path — all three were measured and cleared this session. It is a
per-frame CPU walk over every SkillNode and every Edge, run on every
`vision_render_tick`, which fires every frame for as long as any vision circle
is animating toward its target radius.

This is **North Star #1 work**: stable 144Hz on a 2000-node map. It is not a
tidy-up, and the issues that own it were both sitting in `Backlog` until
2026-08-17.

## Live numbers — have these in hand

RX 7900 XTX, headless, 2000-node `first_level` procgen (3113 edges).
`FogOverlay.set_sources`, the entry point `_refresh` calls per tick:

| owned | sources | set_sources | index build | per-element dimming | frames @144Hz |
|---|---|---|---|---|---|
| 10 | 10 | 3444 us | 22 us | 3390 us | 0.50 |
| 50 | 50 | 5296 us | 72 us | 5210 us | 0.76 |
| 100 | 100 | 15097 us | 124 us | 14750 us | 2.17 |
| 200 | 200 | **78659 us** | 230 us | **77764 us** | **11.33** |

- 78.7 ms/frame at 200 owned is **~12 fps**; the playtest report is 6 fps at 200
  and 15 fps at 100. Right magnitude, right axis, right persistence.
- **99.7% is the dimming pass.** `VisionSourceIndex.build` is 230 us and
  innocent — do not go after the index.
- **Super-linear: 100 -> 200 owned costs 5.3x, not 2x.** Two terms rise
  together: more territory makes more nodes *visible* (only visible nodes take
  the expensive `distances_near` + fold branch), and it packs more circles per
  tile so each fold is longer. O(visible_nodes x circles_per_tile).

Reproduce (fails on purpose — the open defect written as a test):

    mise run test:one -- res://test/perf/bench_fog_refresh_cost.gd

## Ordering, and the one coupling that matters

1. **#414 owns the fix** — nodes self-shade per-fragment against
   `vision_field_darkness` / `ui/vision_field.gdshaderinc`, exactly as #413 did
   for edges. This *deletes* the pass rather than optimising it. Three scope
   forks in its body still need settling (`/swarmify`, or a design conversation)
   — they are about which visual layers self-shade, `SensedOutline`'s
   fixed-alpha treatment, and the #238 sequencing.
2. **#439 narrows to item 1.** Its item 2 is the same work as #414 — decide the
   ownership explicitly before dispatching both, or two agents will write the
   same shader change. Item 1 (`AuraOverlay._refresh` walking every SkillNode
   per allocation signal; a K-node cascade pays K full O(N) rebuilds) is
   genuinely separate, is a plausible second repeater of the same family, and is
   **still unmeasured**. Cheap to measure with the fixture already in
   `bench_fog_refresh_cost.gd` — mount an `AuraOverlay`, drive a cascade, time
   `_refresh`. Do that before scoping its fix.
3. **#238 (node visual encoders, KEEP/MERGE/CUT verdict) is the coupling — and
   it is weaker than #414's body implies.** Checked 2026-08-18: #238 is still
   genuinely open, but its stated blocking decision is **#132 — rune ring vs rim
   diamonds, pick one**. That is a *look* call about which encoders exist. #414
   is about how each encoder *samples fog darkness*. Those are orthogonal
   decisions that happen to touch the same files.

   So the dependency is **file contention and bounded rework, not a logical
   blocker**: if #238 later CUTs an encoder that #414 taught to self-shade, the
   loss is that one encoder's shader change. **The measurement changes the
   calculus** — waiting now has a known price, a ~6 fps late game blocking
   North Star #1 and the LAN milestone. Proceeding on #414 while #238 is open
   is defensible in a way it was not when #414 was filed. Owner's call, and it
   is the single most important line in this file.

   (Board hygiene flags #238 as "In progress with every child closed". That is
   the heuristic miscounting: the remaining work is enumerated in #238's body
   and was never filed as children. Don't read it as done.)

If #238 blocks and the owner does not want the rework: two interim options,
both strictly worse and both leaving the O(elements) walk in place — (a) only
walk elements whose fog value can actually have changed, derivable from the tile
index already built; (b) skip the pass entirely on frames where no circle moved.

## Two dead ends — do not re-derive these

- **The three circle indexes must stay separate.** `VisionCircles` (hard boolean
  union) and `OverlayFieldTileIndex` (soft smin field, GPU-lockstep) look like
  the same grid and are not: different cell-size formulas, different margins
  including a hand-tuned `1e-4` epsilon fixing a *measured* CPU/shader drift with
  0.0013 of headroom, dense vs sparse storage. Investigated and rejected
  2026-08-17; the full reasoning is in `systems/vision_circles.gd`'s docstring.
- **`VisionSourceIndex.build` is not the problem** (230 us at 200 sources).
  #133's fix removed the "x EVERY source" factor from the fold; it never made the
  fold O(1), and the per-element walk was never removed at all. This is the #133
  shape a second time, one layer up.

## Delete this file once #414 lands and #439 item 1 is measured.
