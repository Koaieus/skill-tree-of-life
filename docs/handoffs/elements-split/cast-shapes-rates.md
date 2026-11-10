# Cast shapes: what one point of Fire and one point of Lightning buys

Design research, 2026-11-10; nothing here is decided. Tags: **[M]** measured in the design doc,
**[C]** code or `.tres` constant, **[S]** simulated for this note (method below), **[E]** estimate.

> **Owner, 2026-11-10, after reading this: nothing is decided on the disc multiplier.** *"so far no
> calls made, just still exploring. 2× sounds like a good contender, 3× might be too, depends on how
> we cost lightning?"* The ×2 form is *"i was actually thinking ×2. like twice the node radius = 1
> node diameter"*, one radius for Burning's go-off, its light and the Fire shape. Both multipliers are
> simulated below [S] and priced side by side. What a point of Fire shape costs is, in the owner's
> words, *"very much up to debate"*.

## 1. What the maps look like

- Spacing **[C]**: `min_dist = 2 · max_node_radius() + node_padding` (`procgen/modules/topology.gd:53-58`,
  `docs/domain/procgen.md:12`). First level: ramp cap 50, padding 50, so 150 px
  (`procgen/modules/first_level/topology.tres:11-12`, `node_radius_ramp.gd:25-31`). Coop/versus:
  radius 32, padding 86, also 150 px. Both are 800 nodes at connectivity 0.25.
- Node radius **[C]**: 32 uniform, or 28 to 50 by budget on the first level. So spacing is about
  4.7 node radii, not 2.
- Disc today **[C]**: `radius = node_radius × reach_per_radius (3.0) × power^0.5`
  (`effects/status/spread/explosive_spread.gd:21,26,44-47`); ×2 (radius = √power × node diameter) is
  not in code, so ×3 is today's Explosive disc. A node is hit when any part of it
  touches the disc, `d − candidate.radius <= reach` (`attack/range_finder/euclidean_range_finder.gd:7-9`).
- The design doc leaves the multiplier open, ×2 and ×3 both contenders (`docs/design/elements.md` § The threshold model, "Size").
  On these maps ×2 reaches **no node at all below power 4** (nothing sits closer than 150 px centre to
  centre, so a 32 px node needs a radius of 118 px, power 3.4) and ×3 none below power 2 (power 1.4) [S].
  The earlier reading, `√power × node radius` (×1), reached nothing until power 14 [S].
- No test or doc states "power p reaches n nodes"; `test_explosive_charges.gd:43-64` pins ratios only.

**Simulation [S]**: a Python port of the Bridson sampler and the Delaunay / MST + 25% extras prune
(`poisson_disk_sampler.gd:13`, `procgen_topology.gd:84-146`), rebuilt on 2026-11-10 from those sources
because the first script was not kept; 10 maps of 800 nodes in an auto-sized circular mask, 300
sources each, whole graph, min spacing 150 px, every radius 32 px. Check against the measured table:
its hop-ball counts are 3.0 / 7.8 / 14.5 / 23.0 unique nodes at L = 1..4 against the measured 3.0 / 7.9 /
14.5 / 23.1, and its ×3 disc row (0 / 1.2 / 2.6 / 3.6 / 5.2 / 6.9 / 8.4 at power 1 / 2 / 3 / 4 / 6 / 8 / 10)
matches the one this note first published (the shares differ by a few points: 24% against 26% of casts
hitting nothing at power 2, 70% against 66% covering every neighbour at power 3). Mean edge 175 px. The game was not run; enemy territory is a
subset, so real counts sit lower for both elements. The first-level radius mix (28 to 50 by budget)
is not ported: the ramp is simple, but the budget roll behind it is a scalar field with archetype and
role multipliers. Bracket instead, with the reach kept at the 32 px reference radius and only the
candidates' radius changed: at 28 px the ×2 disc hits 0.5 / 2.1 / 3.5 nodes at power 4 / 6 / 9 and the ×3
disc 1.0 / 2.5 / 3.5 at power 2 / 3 / 4, at 50 px 1.8 / 3.0 / 4.2 and 2.1 / 3.3 / 4.2, against 0.7 / 2.2 / 3.6
and 1.2 / 2.6 / 3.6 at 32 px.

### Fire: other nodes inside a disc of power p (centre excluded) [S]

| p | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 9 | 10 | 12 | 15 | 20 | 30 | 40 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| radius px, ×2 | 64 | 91 | 111 | 128 | 143 | 157 | 181 | 192 | 202 | 222 | 248 | 286 | 351 | 405 |
| nodes hit, ×2 | 0 | 0 | 0 | 0.7 | 1.6 | 2.2 | 3.2 | 3.6 | 4.0 | 4.7 | 5.8 | 7.6 | 11.2 | 14.9 |
| share of casts hitting nothing, ×2 | 100% | 100% | 100% | 45% | 14% | 5% | 0.6% | 0.2% | 0.1% | 0 | 0 | 0 | 0 | 0 |
| share of casts covering every graph neighbour, ×2 | 0 | 0 | 0 | 5% | 20% | 45% | 98% | 99% | 100% | 100% | 100% | 100% | 100% | 100% |
| radius px, ×3 (today's Explosive disc) | 96 | 136 | 166 | 192 | 215 | 235 | 272 | 288 | 304 | 333 | 372 | 429 | 526 | 607 |
| nodes hit, ×3 | 0 | 1.2 | 2.6 | 3.6 | 4.4 | 5.2 | 6.9 | 7.6 | 8.4 | 10.1 | 12.5 | 16.7 | 24.2 | 31.7 |
| share of casts hitting nothing, ×3 | 100% | 24% | 2% | 0.2% | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| share of casts covering every graph neighbour, ×3 | 0 | 11% | 70% | 99% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |

Three thresholds (whole powers, uniform 32 px). At ×2: at least half of casts hit something at
**power 4** (55%; 0% at 3), at least 90% at **power 6** (95%; 86% at 5), at least 90% cover every
graph neighbour at **power 8** (98%; 81% at 7). At ×3: **power 2** (76%; 0% at 1), **power 3** (98%;
76% at 2), **power 4** (99%; 70% at 3). With 28 px candidates the ×2 thresholds become 5 / 6 / 8, with
50 px candidates 3 / 5 / 6. Past power 8 the ×2 disc adds about **0.37 nodes per power**, linearly (11.2
at 30, 14.9 at 40), and the ×3 disc about **0.84**: the same ratio as the areas, 4 to 9. The neighbour
disc holds 3.6 nodes against 3.0 graph neighbours (power 9 at ×2, power 4 at ×3, both radius 192 px):
it also catches near nodes that share no edge. The owner's "2~3 to hit all your neighbors" is 3 to 4
power at ×3 and 8 to 9 at ×2.

**The disc in units of the map's spacing [S].** The radius rides on procgen spacing, which will be
tuned, so the same disc as radius / min spacing (×2 is 0.43 · √p, ×3 is 0.64 · √p at 150 px). Cells are
nodes hit / share hitting nothing / share covering every neighbour, node radius 32 px, whole graph,
10 maps of 800 nodes per column:

| radius / spacing | spacing 120 px | spacing 150 px | spacing 200 px |
|---|---|---|---|
| 0.7 | 0 / 100% / 0 | 0 / 100% / 0 | 0 / 100% / 0 |
| 0.8 | 0.7 / 45% / 5% | 0.2 / 85% / 0 | 0 / 100% / 0 |
| 0.9 | 1.6 / 14% / 20% | 1.2 / 25% / 10% | 0.7 / 48% / 4% |
| 1.0 | 2.3 / 4% / 48% | 1.9 / 8% / 31% | 1.6 / 15% / 19% |
| 1.1 | 2.9 / 1% / 93% | 2.6 / 2% / 66% | 2.2 / 5% / 46% |
| 1.2 | 3.5 / 0 / 99% | 3.2 / 1% / 98% | 2.9 / 1% / 90% |
| 1.5 | 5.1 / 0 / 100% | 4.8 / 0 / 100% | 4.5 / 0 / 100% |
| 2.0 | 8.7 / 0 / 100% | 8.2 / 0 / 100% | 7.8 / 0 / 100% |
| 3.0 | 18.8 / 0 / 100% | 18.1 / 0 / 100% | 17.6 / 0 / 100% |
| 4.0 | 31.8 / 0 / 100% | 31.0 / 0 / 100% | 30.3 / 0 / 100% |

Below 0.7 no node is reached at any spacing (0.4 to 0.6 are all 0 / 100% / 0). It is **not**
spacing-invariant in radius / spacing: the hit test subtracts the candidate's fixed 32 px radius, so
tighter spacing makes the node look bigger. Between 120 and 200 px the nodes hit move by 0.7 to 0.9
around 1.0 and the share covering every neighbour by up to 47 points (at 1.1); the whole curve shifts
by about 32 px / spacing. From 2.0 up the shares are 100% and nodes hit differ by 10% (8.7 against 7.8).
It is exactly invariant in (radius + node radius) / spacing: at 1.1 / 1.2 / 1.3 / 1.5 / 2.0 / 3.0 the
three spacings give identical 1.06 / 1.84 / 2.48 / 3.63 / 6.78 / 15.8 nodes and identical shares (0 below
1.1; 29% / 9% / 3% hitting nothing at 1.1 / 1.2 / 1.3), as geometry scaled with its node radius would
be (the same seeds scale the whole map, so this is a check on the port, not an independent sample). So
a disc authored as a multiple of spacing keeps its meaning if spacing is retuned, and one authored in
node radii keeps it only if node radius moves with spacing.

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
| A1 | Fire, 1 point = 1 blast power, ×2 | 0 | 0 | 0 | 1.6 | 4.0 |
| A1 | same, ×3 | 0 | 1.2 | 2.6 | 4.4 | 8.4 |
| A2 | Fire, 1 point = 2 blast power (owner's idea), ×2 | 0 | 0.7 | 2.2 | 4.0 | 7.6 |
| A2 | same, ×3 | 1.2 | 3.6 | 5.2 | 8.4 | 16.7 |
| A3 | Fire, 1 point = 3 blast power, ×2 | 0 | 2.2 | 3.6 | 5.8 | 11.2 |
| A3 | same, ×3 | 2.6 | 5.2 | 7.6 | 12.5 | 24.2 |
| A4 | Fire, 1 point = 4 blast power, ×2 | 0.7 | 3.2 | 4.7 | 7.6 | 14.9 |
| A4 | same, ×3 (1 point is the neighbour disc) | 3.6 | 6.9 | 10.1 | 16.7 | 31.7 |
| A5 | Fire, 1 point = 5 blast power, ×2 (1 point is about 1 node) | 1.6 | 4.0 | 5.8 | 9.3 | 18.3 |
| A6 | Fire, 1 point = 6 blast power, ×2 (1 point hits something in 95% of casts) | 2.2 | 4.7 | 6.9 | 11.2 | 21.7 |
| A7 | Fire, 1 point = 8 blast power, ×2 (1 point is the neighbour disc) | 3.2 | 6.2 | 9.0 | 14.9 | 28.4 |
| B | Lightning, ring n costs n points (levels at 1, 3, 6, 10) | 3 | 3 | 8 | 8 | 23 |
| C | Lightning, a level at L² ≤ 3 × points (owner's ×3 on the Shocked ladder) | 3 | 8 | 15 | 15 | 33 |
| D | Lightning, 3 nodes per point, largest whole ball that fits (levels at 1, 3, 5, 8, 12) | 3 | 3 | 8 | 15 | 23 |
| E | Lightning, 1 point = +1 hop on the spell's own walk, on a 3-hop fan-all | +9 | +19 | +31 | +62 | much more |

**A. Fire: square-root disc with a multiplier.** "Each Fire adds m blast power; the blast's area
grows with power." A1 is dead at 1 point at either multiplier. At ×3, A2 hits
something in 76% of casts at 1 point and every neighbour at 2, A3 gets every neighbour in 70% of casts at
1 point, and A4 always. At ×2 the same points cost more than twice the power: A1 to A3 are dead at 1
point (the first node needs power 3.4), A4 hits something in 55% of casts, A5 in 86% (1.6 nodes,
every neighbour in 20%), A6 in 95% (every neighbour in 45%), and A7 gets every neighbour in 98%. Against terrain: the
Burning formula with no T to sink and no stacks left behind, the owner's stated reason for a boost.
Weakness: the 1-point result is a probability on ×3 A2 and A3 and ×2 A4 to A6, and the radius reads the seed node's
own radius (28 to 50 px on the first level), so it is target dependent unless the shape disc uses a
fixed reference radius.

**B. Lightning: triangular rings.** "The first ring costs 1 Lightning, the second 2 more, the third
3 more." The seed lands on every node within L hops. Cost per node settles at about 2 nodes per
point. 1 point is live (all neighbours). Matches Fire at the thresholds: 3 / 8 / 15 / 23 nodes
at 1 / 3 / 6 / 10 points, against ×3 with 3 power per point 2.6 / 7.6 / 15.0 / 24.2 and ×2 with 7 power
per point 2.7 / 7.9 / 15.6 / 25.0. Weakness: points 2, 4, 5, 7, 8, 9 buy
nothing, so between thresholds Fire is strictly ahead.

**C. Lightning: the Shocked ladder, tripled.** "Each Lightning is 3 arc power; level L needs L²."
Same law as terrain with T replaced by 1. 1 point is live. Weakness: 3 to 5 nodes per point at
1..3 points (3 / 8 / 15), against ×3 A3's 2.6 / 5.2 / 7.6 and ×2 A7's 3.2 / 6.2 / 9.0, and points 4 and 5 are dead.

**D. Lightning: coverage budget.** "Each Lightning is worth 3 nodes; you get the largest full ball
it pays for." Tracks those two on average: ahead at each threshold, behind between. Weakness: the
thresholds are an authored list, not a rule a player can recite, and points 2, 4, 6, 7, 9 are dead.

**E. Lightning: +1 hop on the spell's own walk, rate authorable per spell.** The mirror of "one Ice
is one hop" (`elements.md:636-641`) and what the doc's shape table says today (`elements.md:566-570`).
No dead point. Weakness: its worth swings by a factor of 15 with the spell, it is the case the
2026-09-02 ruling warns about, it is not the symmetric explosion, and a single-target spell gets nothing.

**Against Ice, all schemes.** If every added landing carries the full seed payload, 1 Fire is
about +2.6 seed-copies (A3 at ×3) or +3.2 (A7 at ×2); 1 Ice is +0.5 on one node and loses a ring. The points are "roughly the same"
only if shape landings carry a share (a neighbour disc at one sixth of the seed each totals +50%), or
if spread is accepted as worth more than focus, which the Ice section already concedes.

## 4. Recommendation

**Fire with Lightning B, sharing one sentence: "one point is one neighbourhood".** The owner leans to
B (*"1 for ring 1, 3 for rings 1+2, etc sounds pretty good"*); the multiplier is still open, so the
price depends on it.

- Fire: the knob is blast power per point on the `ExplosiveSpread` formula, with a fixed reference
  radius. **At ×3, 3 power per point (A3)** tracks B's 3 / 8 / 15 / 23 nodes at 1 / 3 / 6 / 10 points
  best (2.6 / 7.6 / 15.0 / 24.2, rms error 0.7; 2.5 gives 2.0 / 6.5 / 12.5 / 20.4, 3.5 gives 3.1 / 8.8 /
  17.4 / 28.0). **At ×2, 7 power per point** does (2.7 / 7.9 / 15.6 / 25.0, rms 1.1; 6 gives 2.2 / 6.9 /
  13.4 / 21.7 at rms 1.2, 8 gives 3.2 / 9.0 / 17.7 / 28.4 at rms 3.1). At 1 point the ×3 price hits
  something in 98% of casts and every neighbour in 70%; the ×2 price in 98% and 81%. So the cost of ×2
  against ×3 is not a different curve but a price 7 / 3 = 2.3 times higher per point, and a 1-point
  cast that always covers every neighbour needs 4 power per point at ×3 and 8 at ×2.
- Lightning: the seed becomes a hop ball; ring n costs n points. The thresholds are one exported array,
  so D's 1 / 3 / 5 / 8 / 12 is a retune and not a redesign.
- Why: both give about 3 / 8 / 15 / 23 nodes at 1 / 3 / 6 / 10 points. Neither is dead at 1 point,
  picks a neighbour or reads the target. A seed ball leaves `max_hops` alone. Fire is smooth and
  crosses gaps; Lightning is stepped and follows edges.
- Before any Burning work reads the doc's `√power × node diameter` (×2): on real spacing it is dead
  below power 4 and covers every neighbour only from power 8; at ×3 those are power 2 and 4. Burning's
  own power range has to start there, or its go-off will mostly hit nothing.

**Owner questions**

1. Is the Lightning shape a seed that lands on every node within L hops (B, C, D), or extra hops on
   the spell's own walk (E)? Only the first is the symmetric explosion; only the second mirrors Ice.
2. Do shape-added landings carry the full payload or a share? This, not the radius, decides whether
   a Fire or Lightning point is worth an Ice point (+50%).
3. Are dead points on the Lightning ladder acceptable (B: 2, 4, 5), given a caster holds 0..5? If
   not, C (levels at 1, 2, 3) is the only all-live ladder in that range and Fire would move to A4 at ×3,
   or to about 12 power per point at ×2, to keep pace (4.7 / 9.0 / 13.4 nodes at 1 / 2 / 3 points
   against C's 3 / 8 / 15).

Not verified: the real radius mix on first-level maps (32 px assumed, bracketed at 28 and 50), counts inside enemy territory,
values past 8 hops.
