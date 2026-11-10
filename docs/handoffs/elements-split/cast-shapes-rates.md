# Cast shapes: what one point of Fire and one point of Lightning buys

Design research, 2026-11-10; nothing here is decided. Tags: **[M]** measured in the design doc,
**[C]** code or `.tres` constant, **[S]** simulated for this note (method below), **[E]** estimate.

## 1. What the maps look like

- Spacing **[C]**: `min_dist = 2 · max_node_radius() + node_padding` (`procgen/modules/topology.gd:53-58`,
  `docs/domain/procgen.md:12`). First level: ramp cap 50, padding 50, so 150 px
  (`procgen/modules/first_level/topology.tres:11-12`, `node_radius_ramp.gd:25-31`). Coop/versus:
  radius 32, padding 86, also 150 px. Both are 800 nodes at connectivity 0.25.
- Node radius **[C]**: 32 uniform, or 28 to 50 by budget on the first level. So spacing is about
  4.7 node radii, not 2.
- Disc today **[C]**: `radius = node_radius × reach_per_radius (3.0) × power^0.5`
  (`effects/status/spread/explosive_spread.gd:21,26,44-47`). A node is hit when any part of it
  touches the disc, `d − candidate.radius <= reach` (`attack/range_finder/euclidean_range_finder.gd:7-9`).
- The design doc's Burning size is `√power × node radius` with no ×3 (`docs/design/elements.md:110-113`).
  On these maps that formula reaches **no node at all until power 14** [S].
- No test or doc states "power p reaches n nodes"; `test_explosive_charges.gd:43-64` pins ratios only.

**Simulation [S]**: a Python port of the Bridson sampler and the Delaunay / MST + 25% extras prune
(`poisson_disk_sampler.gd:13`, `procgen_topology.gd:84-146`); 10 maps of 800 nodes, 300 sources each,
whole graph, every radius 32 px. Its hop counts reproduce the measured table (4.0 / 8.9 / 15.7 / 24.4
against 4.0 / 8.9 / 15.5 / 24.1). Mean edge 176 px. The game was not run; enemy territory is a
subset, so real counts sit lower for both elements.

### Fire: other nodes inside a disc of power p (centre excluded) [S]

| p | 1 | 2 | 3 | 4 | 6 | 8 | 10 | 12 | 15 | 20 | 30 | 40 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| radius px, code formula (×3) | 96 | 136 | 166 | 192 | 235 | 272 | 304 | 333 | 372 | 429 | 526 | 607 |
| nodes hit | 0 | 1.2 | 2.6 | 3.6 | 5.2 | 6.9 | 8.4 | 10.0 | 12.6 | 16.7 | 24 | 32 |
| share of casts hitting nothing | 100% | 26% | 2% | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| share of casts covering every graph neighbour | 0 | 10% | 66% | 99% | 100% | | | | | | | |
| nodes hit, doc formula (no ×3) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.5 | 1.5 | | |

Past power 4 the code formula adds about **0.84 nodes per power**, linearly. The neighbour disc
holds 3.6 nodes against 3.0 graph neighbours: it also catches near nodes that share no edge. The
owner's "2~3 to hit all your neighbors" describes the ×3 code formula (really 3 to 4), not the doc's.

### Lightning: nodes within L hops of the seed (seed excluded)

| L | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| unique nodes | 3.0 [M] | 7.9 [M] | 14.5 [M] | 23.1 [M] | 33.2 [M] | 45.1 [M] | 61 [S] | 77 [S] | ~115 [E] |
| ring L alone | 3.0 | 4.9 | 6.6 | 8.6 | 10.1 | 11.9 | 14 | 16 | |

Rule of thumb: an L-hop ball holds **(L+1)² − 1** nodes, ring L **2L + 1**. One more hop on a
fan-all walk of H hops buys about 2H + 3 nodes: 9 for Lightning Bolt (`max_hops = 3`), 15 for a
6-hop flood, 1 for a single-path walk. A disc equals an L-hop ball at about 176 / 296 / 407 / 523 px
for L = 1..4 [S], so one hop ring is worth about 116 px (0.77 × spacing) of disc radius.

## 2. The `max_hops` ruling

`docs/domain/spell-propagation.md:444-472`. The owner (2026-09-02): "the latter one we should be
very careful about, and possibly disable entirely until we find a proper way to tune it — adding
max hops to a spell dramatically alters its performance". The doc's conclusion: "Any future
propagation tuning has to be **per-spread-strategy, not a board stat**", because one modifier
means different things per spell (Trailblazer's 999 is a backstop, Cyclone's 8 a limiter).

A forge load is **outside the letter**: a per-cast spend on a per-spell intake row with an authorable
rate, not a board stat or global modifier, and a spell can refuse it (as Ice does, `elements.md:601-610`).
It is **inside the worry**: "+1 hop" is worth 1 to 15+ nodes depending on the spell. A Lightning shape
that adds hops needs a per-spell rate and a refusal for unbounded or self-terminating walks. One that
makes the *seed* a hop ball (candidates B to D) never touches `max_hops`.

## 3. Candidate schemes

Every scheme is statable at the forge and never picks among neighbours. Reference points:
- **Terrain**: a node must first sink T = 2 × degree stacks, about 6 (`elements.md:50`). Burning then
  pays 1 stack per node reached. Shocked reaches L hops at count > L² × T, about 6 / 25 / 56 stacks
  for L = 1 / 2 / 3. A 0..10 count never reaches Shocked level 2 through terrain alone.
- **Ice lean**: +50% of the seed per hop removed, and the walk loses a ring (`elements.md:612-625`).

Nodes reached at 1 / 2 / 3 / 5 / 10 points:

| | Scheme | 1 | 2 | 3 | 5 | 10 |
|---|---|---|---|---|---|---|
| A1 | Fire, 1 point = 1 blast power (code formula) | 0 | 1.2 | 2.6 | 4.4 | 8.4 |
| A2 | Fire, 1 point = 2 blast power (owner's idea) | 1.2 | 3.6 | 5.2 | 8.4 | 16.7 |
| A3 | Fire, 1 point = 3 blast power | 2.6 | 5.2 | 7.6 | 12.6 | 24 |
| A4 | Fire, 1 point = 4 blast power, so 1 point is the neighbour disc | 3.6 | 6.9 | 10.0 | 16.7 | 32 |
| B | Lightning, ring n costs n points (levels at 1, 3, 6, 10) | 3 | 3 | 8 | 8 | 23 |
| C | Lightning, a level at L² ≤ 3 × points (owner's ×3 on the Shocked ladder) | 3 | 8 | 15 | 15 | 33 |
| D | Lightning, 3 nodes per point, largest whole ball that fits (levels at 1, 3, 5, 8, 12) | 3 | 3 | 8 | 15 | 23 |
| E | Lightning, 1 point = +1 hop on the spell's own walk, on a 3-hop fan-all | +9 | +19 | +31 | +62 | much more |

**A. Fire: square-root disc with a multiplier.** "Each Fire adds m blast power; the blast's area
grows with power." A1 is dead at 1 point. A2 hits something in 74% of casts at 1 point and every
neighbour at 2. A3 gets every neighbour in 66% of casts at 1 point; A4 always. Against terrain: the
Burning formula with no T to sink and no stacks left behind, the owner's stated reason for a boost.
Weakness: the 1-point result is a probability on A2 and A3, and the radius reads the seed node's
own radius (28 to 50 px on the first level), so it is target dependent unless the shape disc uses a
fixed reference radius.

**B. Lightning: triangular rings.** "The first ring costs 1 Lightning, the second 2 more, the third
3 more." The seed lands on every node within L hops. Cost per node settles at about 2 nodes per
point. 1 point is live (all neighbours). Matches A3 at the thresholds: 3 / 8 / 15 / 23 nodes
at 1 / 3 / 6 / 10 points, against A3's 2.6 / 7.6 / 15 / 24. Weakness: points 2, 4, 5, 7, 8, 9 buy
nothing, so between thresholds Fire is strictly ahead.

**C. Lightning: the Shocked ladder, tripled.** "Each Lightning is 3 arc power; level L needs L²."
Same law as terrain with T replaced by 1. 1 point is live. Weakness: 3 to 5 nodes per point at
1..3 points, about twice any Fire scheme short of A4, and points 4 and 5 are dead.

**D. Lightning: coverage budget.** "Each Lightning is worth 3 nodes; you get the largest full ball
it pays for." Tracks A3 on average: ahead at each threshold, behind between. Weakness: the
thresholds are an authored list, not a rule a player can recite, and points 2, 4, 6, 7, 9 are dead.

**E. Lightning: +1 hop on the spell's own walk, rate authorable per spell.** The mirror of "one Ice
is one hop" (`elements.md:636-641`) and what the doc's shape table says today (`elements.md:566-570`).
No dead point. Weakness: its worth swings by a factor of 15 with the spell, it is the case the
2026-09-02 ruling warns about, it is not the symmetric explosion, and a single-target spell gets nothing.

**Against Ice, all schemes.** If every added landing carries the full seed payload, 1 Fire (A3) is
about +2.6 seed-copies; 1 Ice is +0.5 on one node and loses a ring. The points are "roughly the same"
only if shape landings carry a share (a neighbour disc at one sixth of the seed each totals +50%), or
if spread is accepted as worth more than focus, which the Ice section already concedes.

## 4. Recommendation

**Fire A3 with Lightning B, sharing one sentence: "one point is one neighbourhood".**

- Fire: 1 point = 3 blast power on today's `ExplosiveSpread` formula, with a fixed reference radius.
  The multiplier is one exported knob.
- Lightning: the seed becomes a hop ball; ring n costs n points. The thresholds are one exported array,
  so D's 1 / 3 / 5 / 8 / 12 is a retune and not a redesign.
- Why: both give about 3 / 8 / 15 / 23 nodes at 1 / 3 / 6 / 10 points. Neither is dead at 1 point,
  picks a neighbour or reads the target. A seed ball leaves `max_hops` alone. Fire is smooth and
  crosses gaps; Lightning is stepped and follows edges.
- Before any Burning work reads the doc's `√power × node radius`: on real spacing it is dead below
  power 14. Either the doc means the code's ×3, or Burning needs a retune of its own.

**Owner questions**

1. Is the Lightning shape a seed that lands on every node within L hops (B, C, D), or extra hops on
   the spell's own walk (E)? Only the first is the symmetric explosion; only the second mirrors Ice.
2. Do shape-added landings carry the full payload or a share? This, not the radius, decides whether
   a Fire or Lightning point is worth an Ice point (+50%).
3. Are dead points on the Lightning ladder acceptable (B: 2, 4, 5), given a caster holds 0..5? If
   not, C (levels at 1, 2, 3) is the only all-live ladder in that range and Fire would move to A4
   to keep pace.

Not verified: the real radius mix on first-level maps (32 px assumed), counts inside enemy territory,
values past 8 hops.
