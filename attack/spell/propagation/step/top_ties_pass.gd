@tool
class_name TopTiesPass
extends RankPass

## Keeps only candidates whose rank ties for first place:
## [code]HIGHEST[/code] → score == max; [code]LOWEST[/code] → score == min.

func filter(
		candidates: Array[SkillNode],
		ranker: NodeRanker,
		payload: CastSpell,
		ctx: PropagationContext,
		_current_node: SkillNode,
		direction: int
	) -> Array[SkillNode]:
	if candidates.is_empty():
		return []

	var scores: Array[float] = []
	for c in candidates:
		scores.append(ranker.score(c, payload, ctx))

	var target: float = scores.max() if direction == TakeTopNStep.Direction.HIGHEST else scores.min()

	var out: Array[SkillNode] = []
	for i in range(candidates.size()):
		if is_equal_approx(scores[i], target):
			out.append(candidates[i])
	return out


func get_description() -> String:
	return "top ties"
