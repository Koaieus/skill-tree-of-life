@tool
class_name MinDamageReducer
extends IncidentReducer

## Resolves to the weakest incident at this node — niche, but enables
## "dampening" spell shapes that punish overlap.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	var merged := _merge_payload_defaults(incidents, node)
	var worst: float = incidents[0].damage
	for inc in incidents:
		if inc.damage < worst:
			worst = inc.damage
	merged.damage = worst
	return merged


func get_description() -> String:
	return "Converging incidents take the weakest."
