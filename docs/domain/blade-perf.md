# Blade sim — cost

Snapshot numbers for the native backend (Ryzen-class desktop, Godot 4.7.1,
headless, 1.2 s swing at `dt = 1/120`, 16 base iterations, shipped defaults
`substeps = 4`, length scaling on). They go stale: rerun the bench rather than
trust a row.

- Solver: `test/perf/bench_blade_sim.gd` (headless SceneTree script; exits
  non-zero without the binary).
- Hit scan: `mise run test:one -- res://test/perf/bench_blade_hit_scan.gd` (a
  `GutTest`, because the scan needs a live `PhysicsDirectSpaceState2D`).
- Prediction: `test/perf/bench_melee_prediction_cost.gd`.

## Solver (native)

| config | time |
|---|---|
| chain k=5 | 0.16 ms |
| chain k=20 | 1.60 ms |
| chain k=30 | 3.39 ms |
| triangulated mesh k=20 | 1.58 ms |
| k=20, `dt=1/30`, 4 iters (the AI coarse tier) | 0.15 ms |

Cost is roughly linear in `steps x substeps x iterations x constraints`
(~0.015 us per constraint projection). Adaptive iterations roughly double the
work; a triangulated mesh doubles the constraints. The native speedup over the
retired GDScript loop was 11-22x and shrinks at the cheap end, where marshalling
packed arrays across the boundary is a fixed per-call cost. Full-fidelity native
is cheaper than the old GDScript coarse tier, so re-measure before building more
tiers on the coarse eval; a two-tier scheme ranks on a different sim than
`resolve()` executes, so any divergence has to be deliberate and tested.

- **A severance costs the no-pop swing plus the re-baked tail**, nothing
  measurable else: the rewind off `prev_samples` is two array copies (~10 us).
  A k=20 chain severed at sample 48 of 144 is ~2.1 ms against 1.6 ms unsevered.
- **A defended swing** (k=100, one wall and one plate on the blade's own
  trajectory, solver only): ~50 ms braced mesh, ~31 ms whip (the `#813` row of
  `bench_blade_sim.gd`; it prints the banked `drag` and peak `strain` because a
  zone placed at the rest span is one a whipped blade never reaches).
- **Substeps and the length axis at k=100:** shipped defaults cost 4.00x the
  flat one-step, no-length-scaling configuration in projections and wall-clock
  (~80 ms to ~320 ms for a whip, solver only), by tuning of
  `LENGTH_ECC_CEILING` / `LENGTH_ITER_SCALE`. Shape-holding improves 2.2x on a
  braced mesh and ~580x on a pure whip. Whether 4x is acceptable inside a turn is
  an owner tuning call.
- **Defender field build:** one `intersect_shape` per pivot, shared by an AI
  rollout's proposals, is 12.7 ms against 18.4 ms at 192 proposals.

## Hit scan

A 100-vertex / 197-edge braced ladder, 145 substeps, 40 defenders:

| defender field | broad phase ON | OFF |
|---|---|---|
| dense (defenders on the swept arc) | ~30 ms | ~29 ms |
| empty sweep | 0.56 ms | 24 ms |

A bound, not a budget: dense is the worst case (the broad phase never rejects
and costs ~3%), empty the best; a real map lives between them. ~30 ms per
resolve at 100 vertices is why the prediction is cached and sliced
(`melee-blade-sim.md`, "The preview is a real resolve"). The remaining cost is
~21600 physics-server shape queries per resolve (297 elements x 145 substeps);
an analytic narrow phase would remove it and let the scan leave the main thread,
but it would make the module encode target geometry, which it refuses to do
(targets publish a `CollisionShape2D`).
