class_name FlatDiffusion
extends DiffusionSpread

## The FLAT seep: a sender `u` moves 1 stack to a masked neighbour `v` iff
## `h_u − h_v ≥ max(min_diff, N_u + M_v)`, where `N_u` counts the masked
## neighbours `u` exceeds by `≥ min_diff` and `M_v` counts the masked
## neighbours exceeding `v` by `≥ min_diff`. The threshold caps what `u` can
## lose and `v` can gain, so a sweep never inverts an edge and strictly lowers
## Σh² whenever it moves anything.

## The smallest height difference that moves a stack.
@export_range(2, 10) var min_diff: int = 2


func _amount(field: StackField, u: NodeCombat, v: NodeCombat, h: Dictionary, memo: Dictionary) -> int:
	var d := _height(field, h, u) - _height(field, h, v)
	if d < min_diff:
		return 0
	var n_key := [&"n", u]
	if not memo.has(n_key):
		memo[n_key] = _lower_count(field, h, u)
	var m_key := [&"m", v]
	if not memo.has(m_key):
		memo[m_key] = _crowding(field, h, v)
	return 1 if d >= maxi(min_diff, int(memo[n_key]) + int(memo[m_key])) else 0


## `N_u`: masked neighbours [param u] exceeds by `≥ min_diff`.
func _lower_count(field: StackField, h: Dictionary, u: NodeCombat) -> int:
	var hu := _height(field, h, u)
	var count := 0
	for w in field.masked_neighbours(u):
		if hu - _height(field, h, w) >= min_diff:
			count += 1
	return count


## `M_v`: masked neighbours of [param v] exceeding it by `≥ min_diff`.
func _crowding(field: StackField, h: Dictionary, v: NodeCombat) -> int:
	var hv := _height(field, h, v)
	var count := 0
	for w in field.masked_neighbours(v):
		if _height(field, h, w) - hv >= min_diff:
			count += 1
	return count
