class_name ModifierBins
extends RefCounted

## First-class holder for the PoE-style pipeline bins. Promoted out of
## Stat so multiple sources (entity + per-node + future temp scopes) can
## compose without one Stat reaching into another's internals.
##
## Each op class composes by **summation across sources** (or a resolved
## product for MULTIPLY), so the pipeline runs **once** on the merged bins:
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
## numbers and walks the multiplier list on read. [method resolve] is the
## door to the merged pipeline as a [FoldTerms] value; [method compute] is
## that plus the fold.

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


## N-source resolve — the ONE fold path. SET short-circuits into
## `set_value`; otherwise sum bins and walk every source's multiplier list
## against THAT source's board (a formula-bound MULTIPLY is meaningless under
## another board, so a merge resolves, never concatenates). The result is
## plain numbers a readout can format without ever re-folding bins.
static func resolve(sources: Array[ModifierBins]) -> FoldTerms:
	var t := FoldTerms.new()
	var win_bins := _pick_set_winner_bins(sources)
	if win_bins != null:
		t.set_value = win_bins.winning_set.get_effective_value(win_bins.board)
		return t
	for b in sources:
		t.add += b.base_add
		t.inc += b.increase_sum
		t.bon += b.bonus_add
		for m in b.multipliers:
			t.mult *= m.get_effective_value(b.board)
	return t


## N-source compose: [method resolve], then the pipeline once. Callers are
## responsible for final type coercion — read through
## [method Stat.get_value_with] rather than calling this directly, so the INT
## floor is not skipped (#895).
static func compute(base: float, sources: Array[ModifierBins]) -> float:
	return resolve(sources).fold(base)


## Single-source compose — the [Stat.get_value] fast path (#470). Same
## arithmetic as [method compute], specialised for the one-source case so a
## warm read never allocates an `Array[ModifierBins]` literal or a
## [FoldTerms]; the arithmetic itself is [method FoldTerms.arith], once.
static func compute_single(base: float, bins: ModifierBins) -> float:
	if bins.winning_set != null:
		return bins.winning_set.get_effective_value(bins.board)
	var mult := 1.0
	for m in bins.multipliers:
		mult *= m.get_effective_value(bins.board)
	return FoldTerms.arith(base, bins.base_add, bins.increase_sum, bins.bonus_add, mult)


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
