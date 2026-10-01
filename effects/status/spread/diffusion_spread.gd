class_name DiffusionSpread
extends StatusSpread

## The "seep" signature: an edge-local FLAT rule. From the sweep's START
## snapshot, a sender `u` moves 1 stack to a masked neighbour `v` iff
## `h_u − h_v ≥ max(min_diff, N_u + M_v)`, where `N_u` counts the masked
## neighbours `u` exceeds by `≥ min_diff` and `M_v` counts the masked
## neighbours exceeding `v` by `≥ min_diff`. Every qualifying edge moves in the
## same sweep. The threshold caps what `u` can lose and `v` can gain, so a
## sweep never inverts an edge and strictly lowers Σh² whenever it moves
## anything — and since every read is of the snapshot, iteration order (and
## `stable_id`) decides nothing.

## The smallest height difference that moves a stack.
@export_range(2, 10) var min_diff: int = 2


## Senders are [method StackField.nodes]; receivers any masked neighbour. A
## receiver outside the field has no adjacency in it; its `M_v` counts 0 —
## harmless under Mine (every Mine neighbour of an owned sender is in the
## owner's field), a caveat for any wider mask.
func on_tick(field: StackField) -> Array[StackTransfer]:
	var out: Array[StackTransfer] = []
	var h := {}
	var crowd := {}  # memo: v -> M_v
	for u in field.nodes():
		var hu := _height(field, h, u)
		var lower: Array[NodeCombat] = []
		for v in field.masked_neighbours(u):
			if hu - _height(field, h, v) >= min_diff:
				lower.append(v)
		var n_u := lower.size()
		for v in lower:
			if not crowd.has(v):
				crowd[v] = _crowding(field, h, v)
			if hu - _height(field, h, v) >= maxi(min_diff, n_u + int(crowd[v])):
				out.append(StackTransfer.new(u, v, 1.0))
	return out


## `M_v`: masked neighbours of [param v] exceeding it by `≥ min_diff`.
func _crowding(field: StackField, h: Dictionary, v: NodeCombat) -> int:
	var hv := _height(field, h, v)
	var count := 0
	for w in field.masked_neighbours(v):
		if _height(field, h, w) - hv >= min_diff:
			count += 1
	return count


## [param n]'s stacks as of the first read this sweep — the start snapshot
## (nothing lands until [SpreadApplier] runs on the whole list).
func _height(field: StackField, h: Dictionary, n: NodeCombat) -> float:
	if not h.has(n):
		h[n] = field.stacks(n)
	return h[n]
