class_name Apportion
extends RefCounted

## Splits a whole-number total over weighted slots, conserving it exactly —
## the house rounding rule for any spread that divides stacks or dose.

const _EPS := 1e-6


## Largest-remainder split of [param total] over [param weights] (ints or
## floats). Each slot first gets the floor of its quota
## [code]total * w / sum(w)[/code]; the units left over go one each to the
## largest fractional remainders. Ties go to the LOWER INDEX — a caller that
## wants another tiebreak (node id, say) orders [param weights] before calling.
## A zero or negative weight counts as zero and never receives a unit.
## Returns one count per weight, summing to [param total]; all zeros when
## [param total] <= 0 or no weight is positive.
static func largest_remainder(total: int, weights: Array) -> Array[int]:
	var alloc: Array[int] = []
	alloc.resize(weights.size())
	alloc.fill(0)
	var ws: Array[float] = []
	var sum := 0.0
	for w in weights:
		var v := maxf(float(w), 0.0)
		ws.append(v)
		sum += v
	if total <= 0 or sum <= 0.0:
		return alloc
	var fracs: Array[float] = []
	var given := 0
	for i in ws.size():
		var quota := total * ws[i] / sum
		var whole := int(floorf(quota + _EPS))
		alloc[i] = whole
		fracs.append(quota - whole)
		given += whole
	# A stable sort keeps the earlier index first on a tie; zero weights never qualify.
	var order: Array = range(ws.size()).filter(func(i: int) -> bool: return ws[i] > 0.0)
	order.sort_custom(func(a: int, b: int) -> bool:
		return fracs[a] > fracs[b] + _EPS or (absf(fracs[a] - fracs[b]) <= _EPS and a < b))
	for k in mini(total - given, order.size()):
		alloc[order[k]] += 1
	return alloc

