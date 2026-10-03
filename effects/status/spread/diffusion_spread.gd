@abstract
class_name DiffusionSpread
extends StatusSpread

## The "seep" family: an edge-local, conserving rule read entirely from the
## sweep's START snapshot. Every masked edge `u→v` with `h_u > h_v` asks the
## subclass's [method _amount] how many stacks move; every qualifying edge
## moves in the same sweep, so iteration order (and `stable_id`) decides
## nothing. Members: [FlatDiffusion] (1 stack past a crowding threshold),
## [FractionDiffusion] (a floored share of the gap).
##
## SHARED and STATELESS like every [StatusSpread]: per-sweep state lives in
## the `h` snapshot and `memo` dictionaries [method on_tick] hands down.


## Senders are [method StackField.nodes]; receivers any masked neighbour. A
## receiver outside the field has no adjacency in it, so any neighbourhood
## count a subclass takes of it reads 0 — harmless under Mine (every Mine
## neighbour of an owned sender is in the owner's field), a caveat for any
## wider mask.
func on_tick(field: StackField) -> Array[StackTransfer]:
	var out: Array[StackTransfer] = []
	var h := {}
	var memo := {}
	for u in field.nodes():
		var hu := _height(field, h, u)
		for v in field.masked_neighbours(u):
			if hu <= _height(field, h, v):
				continue
			var amount := _amount(field, u, v, h, memo)
			if amount >= 1:
				out.append(StackTransfer.new(u, v, float(amount), field.key))
	return out


## Stacks `u` sends `v` this sweep, given `h_u > h_v`. Read heights only via
## [method _height] with [param h] (the snapshot — never [method
## StackField.stacks]); [param memo] is per-sweep scratch for the subclass.
@abstract func _amount(field: StackField, u: NodeCombat, v: NodeCombat, h: Dictionary, memo: Dictionary) -> int


## [param n]'s stacks as of the first read this sweep — the start snapshot
## (nothing lands until [SpreadApplier] runs on the whole list).
func _height(field: StackField, h: Dictionary, n: NodeCombat) -> float:
	if not h.has(n):
		h[n] = field.stacks(n)
	return h[n]
