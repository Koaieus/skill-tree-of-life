@tool
class_name StatRanker
extends NodeRanker

## Reads a stat value off the candidate via [method SkillNode.get_local_stat].
## Use cases: rank by current node_health (Bruiser homes to fattest target),
## by armor (Heavy Bolt), by any future board-stat ranking.

@export var stat_id: StringName = &"node_health"


func score(node: SkillNode, _payload: CastSpell, _ctx: PropagationContext) -> float:
	if node == null:
		return 0.0
	var ls := node.get_local_stat(stat_id)
	if ls == null:
		return 0.0
	var v: Variant = ls.value
	return float(v) if v != null else 0.0


func get_description() -> String:
	return String(stat_id)
