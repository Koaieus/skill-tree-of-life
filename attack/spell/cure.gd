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
## it fully. Stacks are read through [method LandingContext.stacks_of] (world-
## aware), never off the live node: a node cured earlier in this cast reads
## clean.

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
		need += lctx.stacks_of(node, e.status.id) / e.rate
	return need


## The clear plan for [param dose] on [param node]. For each entry in table
## order: [code]cleared = min(stacks, floor(remaining × rate))[/code],
## [code]remaining -= cleared / rate[/code].
##
## Returns [code]{ cleared: Dictionary, spent: float }[/code]:
## [br]- [code]cleared[/code] — [StatusDef] → stacks cleared (float), in table
##   order, ONLY entries that cleared more than 0;
## [br]- [code]spent[/code] — the dose used, Σ cleared / rate. The leftover
##   that flows on is the caller's [code]dose - spent[/code].
## [br]Read-only: it decides counts, it applies nothing.
func plan(node: SkillNode, dose: float, lctx: LandingContext) -> Dictionary:
	var cleared := {}
	var remaining := maxf(dose, 0.0)
	for e in entries:
		if not _usable(e):
			continue
		var stacks := lctx.stacks_of(node, e.status.id)
		var n := minf(stacks, floorf(remaining * e.rate + _EPS))
		if n <= 0.0:
			continue
		cleared[e.status] = n
		remaining = maxf(remaining - n / e.rate, 0.0)
	return {cleared = cleared, spent = maxf(dose, 0.0) - remaining}


func _usable(e: CureEntry) -> bool:
	return e != null and e.status != null and e.rate > 0.0
