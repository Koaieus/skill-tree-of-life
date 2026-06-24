@tool
class_name CancelIfMultiReducer
extends IncidentReducer

## Fizzles where the spell overlaps itself — returns null when ≥2 incidents
## arrive at the same node in the same wave. The CANCEL also kills onward
## propagation from this node (the resolver drops it before expanding).
##
## A signature mechanic: makes spells route AROUND already-touched zones,
## creates interesting topology-puzzle play.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	if incidents.size() > 1:
		return null
	var merged := _merge_payload_defaults(incidents, node)
	merged.damage = incidents[0].damage
	return merged


func get_description() -> String:
	return "Fizzles on overlap (≥2 incidents → no effect)."
