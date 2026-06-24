@tool
class_name FirstReducer
extends IncidentReducer

## Takes the first-arrived incident verbatim, ignoring later arrivals at
## the same node in the same wave. Deterministic (the first incident is
## scene-order stable through the BFS queue). The implicit default when
## [member PropagationConfig.reducer] is null.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	var merged := _merge_payload_defaults(incidents, node)
	merged.damage = incidents[0].damage
	return merged


func get_description() -> String:
	return "First-arrived wins on overlap."
