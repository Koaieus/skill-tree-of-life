@tool
class_name CurrentThresholdPass
extends RankPass

## Keeps only candidates whose rank passes the current node's:
## [code]HIGHEST[/code] → score ≥ current; [code]LOWEST[/code] → score ≤ current.

func filter(
		candidates: Array[SkillNode],
		ranker: NodeRanker,
		payload: CastSpell,
		ctx: PropagationContext,
		current_node: SkillNode,
		direction: int
	) -> Array[SkillNode]:
	var current_score := ranker.score(current_node, payload, ctx)
	var out: Array[SkillNode] = []
	for c in candidates:
		var s := ranker.score(c, payload, ctx)
		var passes := s >= current_score if direction == TakeTopNStep.Direction.HIGHEST else s <= current_score
		if passes:
			out.append(c)
	return out


func get_description() -> String:
	return "≥ current"
