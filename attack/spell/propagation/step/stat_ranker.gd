@tool
class_name StatRanker
extends NodeRanker

## Reads a stat value off the candidate via [method SkillNode.get_local_value].
## Use cases: rank by current node_health (Bruiser homes to fattest target),
## by armor (Heavy Bolt), by any future board-stat ranking.

@export var stat_id: StringName = &"node_health"


func score(node: SkillNode, _payload: CastSpell, _ctx: PropagationContext) -> float:
	if node == null:
		return 0.0
	# A node with no such stat answers null, and `float(null)` is an error rather
	# than a 0 — so this guard is load-bearing, not defensive padding.
	var v: Variant = node.get_local_value(stat_id)
	if v == null:
		return 0.0
	return float(v)


func get_description() -> String:
	return String(stat_id)
