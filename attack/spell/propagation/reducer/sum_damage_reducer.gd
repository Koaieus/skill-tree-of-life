@tool
class_name SumDamageReducer
extends FoldReducer

## Adds all incident damages. The "Resonator" reducer — the spell built to
## be weaponised by self-loops + cycles. Single-incident case is a no-op
## (damage carries through unchanged).


func _fold_damage(incidents: Array[CastSpell]) -> float:
	var total: float = 0.0
	for inc in incidents:
		total += inc.damage
	return total


func get_description() -> String:
	return "Converging incidents add."
