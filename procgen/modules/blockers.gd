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
##
## [b]Rebalanced in #777.[/b] The defaults were 10/25/100 when a Dormant Core
## held exactly one node; a footprint roughly triples its board share, and that
## combination would have put ~42% of an 800-node map under a blocker. 30/50/100
## is 50 blockers and ~20.5% owned — and the lobby's "Regular" rung is authored
## to the same three numbers, so a direct sandbox launch and the lobby's normal
## play the same game.
##
## The rest of the lobby ladder (`ui/frontmatter/lobby_options/blocker_options.tres`)
## was re-pitched against the same footprint cost, since every rung got denser
## for free: Few 40/80/125, Lots 20/35/70 (~29% owned), Heavy 15/25/50 (~41%).
## The old Lots (6/14/50) and Heavy (5/8/25) claimed 74% and >100% of the board
## respectively once footprints landed — "Heavy" would have silently degraded
## into "every eligible node is a blocker", because a tier count clamps to the
## eligible pool and footprints shrink to fit. A rung has to stay PLACEABLE to
## mean anything.
@export_range(0, 200, 1, "or_greater") var blocker_per_small: int = 30
@export_range(0, 200, 1, "or_greater") var blocker_per_medium: int = 50
@export_range(0, 200, 1, "or_greater") var blocker_per_large: int = 100

## Bonus-node FOOTPRINT per tier (#777). A Dormant Core no longer holds only the
## node it sits on: at placement time it rolls `randi_range(min, max)` extra
## nodes and grows into them, so size finally reads on the BOARD as territory
## rather than only in a tooltip.
##
## The roll is uniform and inclusive on both ends, so a small can still land on
## `0` and behave exactly like the pre-#777 blocker. Growth is a randomized
## frontier walk over nodes adjacent to what the blocker already holds — the
## footprint is always CONNECTED, which is what makes the falloff aura's
## hop-from-core well-defined over the owned subgraph.
##
## [b]The range IS the clamp on the falloff.[/b] `blocker_footprint_falloff.tres`
## deducts 5 `node_health` per hop from the core with no floor of its own, and
## the only thing keeping that off zero is that a footprint of `n` nodes reaches
## at most hop `n`. Raising a max past `authored node_health / 5` gives the far
## rim of a big blocker nothing to lose (large: 80/5 = hop 16; small: 20/5 = 4).
##
## Never a hard guarantee: a blocker short of eligible neighbours (map edge,
## another blocker's claim, a starter's safe radius) shrinks its footprint to
## what fits rather than dropping the blocker or stealing a claimed node.
@export_range(0, 12, 1) var footprint_small_min: int = 0
@export_range(0, 12, 1) var footprint_small_max: int = 2
@export_range(0, 12, 1) var footprint_medium_min: int = 2
@export_range(0, 12, 1) var footprint_medium_max: int = 4
@export_range(0, 12, 1) var footprint_large_min: int = 4
@export_range(0, 12, 1) var footprint_large_max: int = 6


## The `[min, max]` bonus-node range for a [GameRoot.BlockerSize] int, ordered
## and floored at 0 so an inspector typo (max below min) narrows to a point
## instead of making `randi_range` fail.
func footprint_range(size: int) -> Vector2i:
	var lo := footprint_small_min
	var hi := footprint_small_max
	if size == 1:
		lo = footprint_medium_min
		hi = footprint_medium_max
	elif size == 2:
		lo = footprint_large_min
		hi = footprint_large_max
	lo = maxi(0, lo)
	return Vector2i(lo, maxi(lo, hi))


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
