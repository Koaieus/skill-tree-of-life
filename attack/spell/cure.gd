@tool
class_name Cure
extends Resource

## What one cleanse cures and at what price: the single owner of that table.
## A [CureEffect] and a [NeedSplitSpread] hold the SAME [Cure] by reference,
## so the drain and the split never disagree about price.
##
## One dose, priced per status: each [CureEntry] clears
## [member CureEntry.rate] stacks per unit of dose, entries clear in table
## order, and a node's [b]need[/b] ([method need_of]) is the dose that cures
## it fully. Stacks are read through [method LandingContext.spot_stacks_of]
## (world-aware), never off the live node: a node cured earlier in this cast
## reads clean.
##
## [b]Core first.[/b] On a core node the spot has two holders, the core (its
## owner's entity rows) and the node; the dose clears the core's rows in table
## order, then the node's. Splitting by need instead is a swap inside
## [method plan].

## Cleared in this order; an entry with no status or a non-positive rate is
## skipped.
@export var entries: Array[CureEntry] = []

## Absorbs float noise in `floor(remaining × rate)` (0.1 × 30 = 2.9999…).
const _EPS := 1e-6


## The dose that cures [param node] fully: Σ stacks_i / rate_i. 0 on a clean
## node — the split weight and the "is there anything to cure" test.
func need_of(node: SkillNode, lctx: LandingContext) -> float:
	var need := 0.0
	for e in entries:
		if not _usable(e):
			continue
		need += lctx.spot_stacks_of(node, e.status.id) / e.rate
	return need


## The clear plan for [param dose] on [param node]. For each entry in table
## order: [code]cleared = min(stacks, floor(remaining × rate))[/code],
## [code]remaining -= cleared / rate[/code].
##
## Returns [code]{ core_cleared: Dictionary, cleared: Dictionary, spent: float }[/code]:
## [br]- [code]core_cleared[/code] — [StatusDef] → stacks cleared off the core
##   (see the class doc), planned before the node; empty off a core node;
## [br]- [code]cleared[/code] — [StatusDef] → stacks cleared off the node, in
##   table order, ONLY entries that cleared more than 0;
## [br]- [code]spent[/code] — the dose used, Σ cleared / rate. The leftover
##   that flows on is the caller's [code]dose - spent[/code].
## [br]Read-only: it decides counts, it applies nothing.
func plan(node: SkillNode, dose: float, lctx: LandingContext) -> Dictionary:
	var left := [maxf(dose, 0.0)]
	var core_cleared := _drain(left, func(id: StringName) -> float: return lctx.core_stacks_of(node, id))
	var cleared := _drain(left, func(id: StringName) -> float: return lctx.stacks_of(node, id))
	return {core_cleared = core_cleared, cleared = cleared, spent = maxf(dose, 0.0) - left[0]}


## One holder's pass over the table: clears what [code]left[0][/code] (the
## dose remaining, a one-element box) buys of [param stacks_of]'s rows and
## spends it.
func _drain(left: Array, stacks_of: Callable) -> Dictionary:
	var cleared := {}
	for e in entries:
		if not _usable(e):
			continue
		var stacks: float = stacks_of.call(e.status.id)
		var n := minf(stacks, floorf(left[0] * e.rate + _EPS))
		if n <= 0.0:
			continue
		cleared[e.status] = n
		left[0] = maxf(left[0] - n / e.rate, 0.0)
	return cleared


func _usable(e: CureEntry) -> bool:
	return e != null and e.status != null and e.rate > 0.0
