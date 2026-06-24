@tool
class_name MaxDamageReducer
extends IncidentReducer

## Resolves to the strongest incident at this node — the sanity floor for
## spells that fan widely but shouldn't compound when they overlap.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	var merged := _merge_payload_defaults(incidents, node)
	var best: float = incidents[0].damage
	for inc in incidents:
		if inc.damage > best:
			best = inc.damage
	merged.damage = best
	return merged


func get_description() -> String:
	return "Converging incidents take the strongest."
