@tool
class_name SumDamageReducer
extends IncidentReducer

## Adds all incident damages. The "Resonator" reducer — the spell built to
## be weaponised by self-loops + cycles. Single-incident case is a no-op
## (damage carries through unchanged).


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	var merged := _merge_payload_defaults(incidents, node)
	var total: float = 0.0
	for inc in incidents:
		total += inc.damage
	merged.damage = total
	return merged


func get_description() -> String:
	return "Converging incidents add."
