@tool
class_name CatalystSpread
extends StatusSpread

## The catalyst status's spread: the death burn ([method on_removed]) and the
## [member resonance] the blade's piece pass weighs a shared chunk by. No stat
## targets either, so they live here as knobs
## (`docs/domain/stat-knobs-and-bins.md` §1).
##
## Death ([method on_removed]): a killed node spends every charge at once —
## one burn transfer, nothing spills onto a neighbour.

## Death-blast damage per charge spent; one blast in all. Tentative, easy to
## change (no owner number; linear vs √ vs cap is a playtest call).
@export_range(0.0, 100.0, 0.5, "or_greater") var damage_per_charge: float = 2.0
## The shared chunk's weight on each side of a blade contact's power
## (`BladePopResolver`). Tentative, easy to change.
@export_range(0, 5, 1, "or_greater") var resonance: int = 1
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
	return "When the node is %s, every charge goes off in one blast for %s damage per charge." % [
			when, NumFmt.num(damage_per_charge)]
