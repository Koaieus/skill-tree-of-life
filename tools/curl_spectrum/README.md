# Curl spectrum (#705)

**Informative only — the same standing as `tools/balance/`.** This produces
numbers and a recommendation; freezing a coefficient is an owner pinning call
(D-13), never an implementing agent's. `cyclone.tres` is untouched by #705.

## What this is

Cyclone's propagation, measured as a **linear operator on directed edges**
instead of simulated. Keep a front's state on the edge it arrived along and
`CycloneStep` becomes a fixed non-negative matrix: growth per wave is its
spectral radius, by power iteration on `2|E| x 2|E|`, no cast required. That is
how #703's table was produced; #705 pointed the same operator at the ground
procgen actually makes.

```
mise run curl-spectrum                # 400-node maps, 4 seeds, 6 targets — ~70s
mise run curl-spectrum -- 800 4 6     # nodes, seeds, targets per map
```

Output is a five-table markdown report, printed and written to `snapshot.md`
(committed — a retune shows up as a diff here).

## Files

- `curl_terrain.gd` — positions + adjacency, and the BFS ball that stands in for
  one entity's territory. No scenes, no ownership: only geometry and topology
  can move a curl.
- `curl_operator.gd` — the operator itself: build, `apply` (one wave),
  `spectral_radius`, `wave_energies` (the finite `max_hops = 8` walk). Reads its
  ranking from `Curl.rank_indices`, the same call the shipped step makes.
- `curl_lattices.gd` — the idealised terrains #703 tuned against, as the
  calibration column.
- `curl_procgen_terrain.gd` — stages 1–3 of the real pipeline
  (`PoissonDiskSampler.sample` → `GraphProcgen._triangulate_and_prune`) and
  nothing else.
- `curl_cast_probe.gd` — real `SpellResolver` casts, for the rules the operator
  cannot represent.
- `spectrum_harness.gd` / `spectrum_report.gd` / `run_spectrum.gd` — the sweep,
  its markdown, and the `SceneTree` entry point.

Run it through the mise task. The cast probe has been seen to stall under a
bare `godot --script` invocation of `run_spectrum.gd`, and never once through
`mise run curl-spectrum`.

`test/unit/spell/test_curl_spectrum.gd` is the acceptance gate: it pins the
operator against #703's published table (tree 0.000, any ring 0.650, hex wheel
1.159, 37-node lattice 1.326). A measuring device that drifts is worse than
none.

## Reading the tables — three traps

1. **Table B (whole-map ρ) is a ceiling, not a reading.** A dominant eigenvalue
   localises onto the densest patch *anywhere* on the map, so it answers
   "somewhere here, a storm could sustain" — never "a cast here does". Table C's
   territory balls are the playable number, and they run ~0.05 lower.
2. **ρ is not a bound on a real cast, in either direction.** The resolver merges
   N converging fronts into ONE payload that then fans ONCE, where the operator
   keeps them as N states that each fan in full — so convergence loses arms even
   while it sums damage, and the cast runs *below* the operator on sparse
   ground. `closing_gain` pushes the other way on dense ground. Table E measures
   the gap rather than arguing about it; ±30% by wave 8 at the shipped
   connectivity. On a tree the two agree exactly, which is the case the floor
   question rests on.
3. **The territory restriction barely costs anything at `max_hops = 8`.** Table
   D reports `territory / whole map` and the two differ by ~2%: eight waves do
   not outrun a 60-node holding, so `OwnerFilter` is not what limits a cast's
   damage. It matters for ρ — an asymptotic reading of a bounded holding is
   ~0.05 lower than the map's — and not for the finite walk.
4. **ρ = 0.000 does not mean "deals nothing".** A cast is eight waves, not a
   limit: on an MST (`connectivity = 0`) Cyclone still totals ~4.4x its seed
   impact, because a non-backtracking fan covers a lot of ground on the way
   down. The spell is not dead there — it is a 4x spell instead of an 18x one.

## What the 2026-09-01 run found

Against `connectivity = 0.25`, which is what **both** shipped topology modules
author (`procgen/modules/first_level/topology.tres`,
`procgen/modules/coop_versus/topology.tres` — the module *default* of 0.55
ships nowhere), 400-node maps, 4 seeds, 6 targets each:

- **Playable ground does contain the terrain the spell is built for, with room
  to spare.** The floor — where a territory's ρ crosses 1 — sits at
  `connectivity` **0.10–0.15** for a 60-node holding and **0.20–0.25** for a
  20-node one, against a shipped 0.25. Below 0.05 nothing sustains anywhere.
- **Territory size is the sharper axis than connectivity.** At what ships, 96%
  of 60-node holdings are self-sustaining (mean ρ 1.10) but only 75% of 20-node
  ones (mean ρ 1.02). A fresh camp is genuinely marginal ground for a storm and
  a mid-run holding is not — which is the spell reading terrain rather than
  failing, but it does mean Cyclone comes online *with* a player's territory.
  The model is generous here: territory really is grown as a ball (the shipped
  [TerritorySeeder] runs a `GreedyBfsBallPolicy`), but a ball takes a whole ring
  before moving out, so it is the densest holding of its size — a stringier real
  territory pushes the floor up, never down.
- **A tree is not dead ground, it is cheap ground.** At `connectivity = 0`
  procgen prunes to an MST and ρ is exactly 0.000, but a cast still totals
  **4.4x** its seed impact over eight waves, against 18x at what ships. The
  spell's floor is "a quarter as good", not "nothing".
- **`0.80/0.30` is the weakest of the three candidates**, and not by a little:
  it reads 0.800 on a lone ring against 1.100 on a dense lattice — a contrast of
  1.4x where `0.65/0.45/0.25` gets 2.0x. The two-rank fan flattens exactly the
  terrain typing the spell exists for, and at shipped connectivity it sits at
  ρ 1.02, on the knife edge.
- **The shipped `0.70/0.40/0.20` and the wider `0.65/0.45/0.25` behave alike**,
  the latter about 10% hotter everywhere (20.4x vs 18.4x per cast at shipped
  connectivity) with a slightly cleaner ring-vs-lattice split. Either holds; the
  choice is a feel call, not a threshold one.
- **`closing_gain = 1.35` is doing real work, at roughly the right size.** At
  gain 1.0 a real cast lands ~30% under the operator's prediction (the merge
  collapse), at 1.35 it lands on it, and at 1.70 it overshoots hard on dense
  ground — 67x seed damage at `connectivity = 0.55` against 42x at 1.35. The
  knob is the one with the steepest tail risk if map density ever rises.
