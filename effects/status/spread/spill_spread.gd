@tool
class_name SpillSpread
extends StatusSpread

## A removed node's raw stacks spill onto its own direct masked neighbours
## that survive the beat (not in the removed union — judged against the
## field's state from before removal). Per-node: each removed node is its
## own self-contained spill, never chained with another removed node's
## result in the same call, so shuffling the `removed` array never changes
## the output multiset. No survivor → the stacks vanish (one burn transfer).

## Fraction of a removed node's raw stacks eligible to spill at all, before
## the even split across survivors. `1.0` = a removed node's whole row is
## eligible; lower leaves the rest to vanish with the node.
@export_range(0, 1) var spread_fraction: float = 1.0

## Which removal causes this rule fires for, as [constant StatusSpread.CAUSE_DEATH]
## / [constant StatusSpread.CAUSE_DEALLOC] bits. Default: both.
@export_flags("Death", "Dealloc") var triggers: int = 3

## Neighbours (as [method SkillNode.ownership_bit] bits, same flag set as
## [member StatusSpread.ownership_mask]) that count in the divisor and absorb
## their share without receiving a transfer — the dissipating spill. `0` = none.
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8") var sink_mask: int = 0

## Extra multiplier on [member spread_fraction] when the cause is a death strip;
## `1.0` = a kill spills as much as a dealloc.
@export_range(0, 1) var death_fraction: float = 1.0


func on_removed(field: StackField, removed: Array[NodeCombat], cause: int) -> Array[StackTransfer]:
	var out: Array[StackTransfer] = []
	if cause & triggers == 0:
		return out
	var removed_set := {}
	for r in removed:
		removed_set[r] = true
	for r: NodeCombat in removed:
		var stacks: float = field.stacks(r)
		if stacks <= 0.0:
			continue
		var fraction: float = spread_fraction * death_fraction if cause == CAUSE_DEATH else spread_fraction
		# The doom scale multiplies past the fraction's [0, 1] clamp: a doomed
		# node can spill more than it held.
		var spilled := _split(field, r, floor(stacks * fraction * field.spill_scale(r)), removed_set)
		var remainder: float = stacks
		for t in spilled:
			remainder -= t.amount
		out.append_array(spilled)
		if remainder > 0.0:
			out.append(StackTransfer.new(r, null, remainder, field.key))
	return out


## The spill [method on_removed] would ring for [param node] dying now, over
## [param share] of its row: the same survivors, sinks and even split, but
## nothing is removed and nothing burned — a quote, see
## [method StatusSpread.copy_out]. Fires only if this rule fires on a death.
func copy_out(field: StackField, node: NodeCombat, share: float) -> Array[StackTransfer]:
	if triggers & CAUSE_DEATH == 0 or node == null:
		return [] as Array[StackTransfer]
	var stacks: float = field.stacks(node)
	if stacks <= 0.0:
		return [] as Array[StackTransfer]
	var spillable: float = floor(stacks * share * spread_fraction * death_fraction * field.spill_scale(node))
	return _split(field, node, spillable, {node: true})


## [param spillable] of [param r]'s stacks split evenly, floored, over its
## masked neighbours outside [param removed_set]; each [member sink_mask]
## neighbour takes a share that is never transferred.
func _split(field: StackField, r: NodeCombat, spillable: float, removed_set: Dictionary) -> Array[StackTransfer]:
	var out: Array[StackTransfer] = []
	var survivors: Array[NodeCombat] = []
	for m in field.masked_neighbours(r):
		if not removed_set.has(m):
			survivors.append(m)
	var k := survivors.size()
	if k == 0:
		return out
	var sinks := _sink_count(field, r, removed_set, survivors)
	var share: float = floor(spillable / (k + sinks))
	if share > 0.0:
		for survivor in survivors:
			out.append(StackTransfer.new(r, survivor, share, field.key))
	return out


## Surviving neighbours of [param r] in [member sink_mask] that are not
## already receivers.
func _sink_count(field: StackField, r: NodeCombat, removed_set: Dictionary, receivers: Array[NodeCombat]) -> int:
	if sink_mask == 0:
		return 0
	var n := 0
	for m in field.neighbours_in(r, sink_mask):
		if not removed_set.has(m) and not receivers.has(m):
			n += 1
	return n


func describe() -> String:
	var when := cause_phrase(triggers)
	if when.is_empty() or spread_fraction <= 0.0:
		return ""
	var text := "When the node is %s, %s%% of its stacks spill evenly onto its surviving neighbours" % [
			when, NumFmt.num(spread_fraction * 100.0)]
	if triggers & CAUSE_DEATH and death_fraction < 1.0:
		text += " (%s%% of that on a kill)" % NumFmt.num(death_fraction * 100.0)
	if sink_mask & 1:
		text += "; unowned neighbours soak up their share"
	return text + "."
