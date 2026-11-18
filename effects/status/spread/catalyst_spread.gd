@tool
class_name CatalystSpread
extends StatusSpread

## The Catalyst status's spread: the death burn ([method on_removed]). A
## removed node's Catalyst stacks are written off at once — one burn transfer
## that deals no damage, nothing spills onto a neighbour. Catalyst never goes
## off; the burn only clears the row.

## Which removal causes write the row off, as [constant StatusSpread.CAUSE_DEATH]
## / [constant StatusSpread.CAUSE_DEALLOC] bits. Default: a kill only.
@export_flags("Death", "Dealloc") var triggers: int = CAUSE_DEATH

## A removed node's Catalyst stacks all go at once: one burn of the whole row per
## removed node, never a share onto a survivor.
func on_removed(field: StackField, removed: Array[NodeCombat], cause: int) -> Array[StackTransfer]:
	var out: Array[StackTransfer] = []
	if cause & triggers == 0:
		return out
	for r in removed:
		var stacks: float = field.stacks(r)
		if stacks > 0.0:
			out.append(StackTransfer.new(r, null, stacks, field.key))
	return out


func describe() -> String:
	var when := cause_phrase(triggers)
	if when.is_empty():
		return ""
	return "When the node is %s, its Catalyst is written off at once, dealing no damage; none passes to a neighbour." % when
