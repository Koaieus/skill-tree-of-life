class_name ModifierBins
extends RefCounted

## First-class holder for the PoE-style pipeline bins. Promoted out of
## Stat so multiple sources (entity + per-node + future temp scopes) can
## compose without one Stat reaching into another's internals.
##
## Each op class composes by **summation across sources** (or list-concat
## for MULTIPLY), so the pipeline runs **once** on the merged bins:
##
##   result = (base + Σ_all base_add)
##         × (1 + Σ_all increase_sum / 100)
##         × Π_all multipliers
##         + Σ_all bonus_add
##
## This is the load-bearing property that makes per-node localization
## correct: chaining pipelines (entity result → local base) double-applies
## INCREASEs against MULTIPLYs, but bin merge does not.
##
## Bin maintenance lives on Stat (add_modifier/remove_modifier mutate the
## bins owned by that Stat). ModifierBins is dumb — it just carries the
## numbers and walks the multiplier list on read.

var base_add: float = 0.0
var increase_sum: float = 0.0
var bonus_add: float = 0.0
var multipliers: Array[StatModifier] = []
var winning_set: StatModifier = null
## The board these bins' modifiers are bound on — mirrored from the owning
## [Stat]'s own `_board` (#377). [method compute] is static (no Stat in
## scope), so a formula-bound SET/MULTIPLY modifier needs its board to travel
## WITH its bins, not as one shared parameter: a multi-source compose (entity
## bins + node bins) has a different correct board per source.
var board: StatBoard = null


## N-source compose. SET short-circuits; otherwise sum bins, walk all
## multiplier lists, run the pipeline once. Callers are responsible for
## final type coercion via Stat._coerce.
static func compute(base: float, sources: Array[ModifierBins]) -> float:
	var win_bins := _pick_set_winner_bins(sources)
	if win_bins != null:
		return win_bins.winning_set.get_effective_value(win_bins.board)
	var add := 0.0
	var inc := 0.0
	var bon := 0.0
	var mult := 1.0
	for b in sources:
		add += b.base_add
		inc += b.increase_sum
		bon += b.bonus_add
		for m in b.multipliers:
			mult *= m.get_effective_value(b.board)
	# Clamp (1 + Σ INCREASE/100) at 0: large stacks of negative INCREASE zero
	# the stat out rather than flipping its sign. Net inc below -100% is a
	# legitimate gameplay state (think "nerf modifier" pool entries on INT);
	# the floor keeps the math predictable and the result interpretable as
	# "× 0 + BONUS" for downstream consumers.
	return (base + add) * maxf(0.0, 1.0 + inc / 100.0) * mult + bon


## SET tiebreak across sources: highest priority wins; at equal priority
## the LAST source listed wins. Consumers order sources so the most
## specific scope is LAST (the combined read passes [entity.bins, node.bins] so
## a local SET at equal priority overrides the entity-side one). Returns the
## winning SOURCE (not just the modifier) so [method compute] can read its
## `board` alongside its `winning_set`.
static func _pick_set_winner_bins(sources: Array[ModifierBins]) -> ModifierBins:
	var best: ModifierBins = null
	for b in sources:
		if b.winning_set == null:
			continue
		if best == null or b.winning_set.priority >= best.winning_set.priority:
			best = b
	return best
