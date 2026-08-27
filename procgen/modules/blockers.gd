@tool
class_name GraphProcgenBlockers
extends Resource

## Removable blockers module (#300, #349). Blocker density + safety knobs —
## the ones a lobby's Blockers None..Heavy control turns. Save as its own
## top-level `.tres` under `procgen/modules/<preset>/` and reference it by
## path from [GraphProcgenConfig.blockers] — never embed it as a SubResource
## (#349 D3).

## Safety floor for the [member blocker_per_small] / [member blocker_per_medium]
## / [member blocker_per_large] denominators, applied at the point of use in
## [GraphProcgen._place_blocker_indices]. A positive denominator below this densifies
## the tier into the hundreds (e.g. denom 1 → one blocker per node), so the
## placement pass clamps it up to here — a joker authoring `1` in the inspector
## still gets `5` at runtime, never "a blocker on every node".
const MIN_BLOCKER_PER := 5

## Blocker placement density per tier (#477). [GraphProcgen] places
## `floor(node_count / blocker_per_<size>)` blockers of each size, sampled
## uniformly without replacement among regular nodes (never a starter core or
## a keystone node). `0` disables a tier; any positive denominator below
## [constant MIN_BLOCKER_PER] is clamped up to it at placement time. The
## `size` value in a returned placement is the [GameRoot.BlockerSize] int
## (0/1/2).
@export_range(0, 200, 1, "or_greater") var blocker_per_small: int = 10
@export_range(0, 200, 1, "or_greater") var blocker_per_medium: int = 25
@export_range(0, 200, 1, "or_greater") var blocker_per_large: int = 100

## Safe radius around every camp core (#300): no blocker may spawn within this
## many hops of ANY starter core — the human's and every AI camp's alike, since
## at procgen time a core is just a starter index and nothing yet knows which
## camp a seat will drive. `0` disables the exclusion.
##
## Measured against the first_level preset (800 nodes, 7 starters, pruned
## Delaunay mesh at connectivity 0.25): a 5-hop ball excludes ~205 nodes
## (~26% of the map), a 6-hop ball ~266 (~33%). The eligible pool shrinking
## below the requested blocker count places FEWER blockers — it never falls
## back to the excluded ring.
@export_range(0, 12, 1) var blocker_min_hops_from_core: int = 6

## Shape of the #586 loot-book prune every blocker runs at spawn: it pops
## random spells off a COPY of its tier's authored book until a roll fails,
## so two runs of the same tier offer different slices — and sometimes none.
##
## This is the `m` in [method SpellBook.duplicate_pruned]'s `n / (n + m)`
## chain; see there for the exact distribution. `1.0` makes every outcome in
## `{0..n}` equally likely, which is both maximum variation and the stingiest
## setting in the sane range.
##
## [b]Turn this DOWN to slow how fast spells spread, never up.[/b] Raising it
## collapses the chance a kill offers nothing (at `n == 4`: 20% at 1.0, 2.9%
## at 3.0), which is the opposite of what the knob exists for.
@export_range(0.5, 3.0, 0.05) var blocker_spell_prune_m: float = 1.0
