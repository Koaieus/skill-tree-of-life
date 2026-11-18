@tool
class_name CatalystSpread
extends StatusSpread

## The catalyst status's spread: the death burn ([method on_removed]). A
## removed node's charges are written off at once — one burn transfer that
## deals no damage, nothing spills onto a neighbour.

## Which removal causes spend the charges, as [constant StatusSpread.CAUSE_DEATH]
## / [constant StatusSpread.CAUSE_DEALLOC] bits. Default: a kill only.
@export_flags("Death", "Dealloc") var triggers: int = CAUSE_DEATH

## A removed node's charges all go at once: one burn of the whole row per
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
	return "When the node is %s, its charges are spent at once; none pass to a neighbour." % when
