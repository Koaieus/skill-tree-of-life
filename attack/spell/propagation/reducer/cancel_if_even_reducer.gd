@tool
class_name CancelIfEvenReducer
extends IncidentReducer

## Fizzles when the incident count at this node is EVEN (0 never reaches
## reduce; 2, 4, … cancel). Pairs interestingly with branching shapes
## where odd-vs-even parity flips by topology.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	if incidents.size() % 2 == 0:
		return null
	var merged := _merge_payload_defaults(incidents, node)
	merged.damage = incidents[0].damage
	return merged


func get_description() -> String:
	return "Fizzles on even-count overlap."
