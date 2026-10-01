class_name FractionDiffusion
extends DiffusionSpread

## The FRACTION seep — floored Metropolis: every masked edge `u→v` with
## `h_u > h_v` moves `⌊fraction · (h_u − h_v) / (1 + max(deg_u, deg_v))⌋`
## stacks, `deg` the [method StackField.masked_degree]. The floor keeps the
## remainder on the sender, so the total is conserved; Σh² strictly falls on
## every sweep that moves anything, and no node leaves its closed
## neighbourhood's `[min, max]`. It does NOT promise no-inversion: a gap-scaled
## share can overshoot an edge for one sweep (`2 – 40 – 10` → `14 – 18 – 20`),
## which the next sweep corrects. Hubs throttle flow — connectedness cures.
##
## A receiver outside the field has no adjacency in it, so its
## `masked_degree` reads 0 and the bound under-counts — harmless under the
## default Mine mask, a caveat for any wider one.

## The share of the way to each edge's local equilibrium that moves per
## sweep. Lower settles slower and coarser: flow freezes on any edge whose gap
## is below `(1 + max deg) / fraction`.
@export_range(0.01, 1.0, 0.01) var fraction: float = 1.0


func _amount(field: StackField, u: NodeCombat, v: NodeCombat, h: Dictionary, memo: Dictionary) -> int:
	var d := _height(field, h, u) - _height(field, h, v)
	return floori(fraction * d / (1 + maxi(_degree(field, memo, u), _degree(field, memo, v))))


func _degree(field: StackField, memo: Dictionary, n: NodeCombat) -> int:
	if not memo.has(n):
		memo[n] = field.masked_degree(n)
	return memo[n]
