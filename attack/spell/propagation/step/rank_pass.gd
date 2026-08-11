@tool
@abstract
class_name RankPass
extends Resource

## Narrows a candidate set before [TakeTopNStep] sorts and picks the top N.
## Each pass is a reduction: candidates → fewer candidates.

@abstract func filter(
		candidates: Array[SkillNode],
		ranker: NodeRanker,
		payload: CastSpell,
		ctx: PropagationContext,
		current_node: SkillNode,
		direction: int  # TakeTopNStep.Direction
	) -> Array[SkillNode]


func get_description() -> String:
	return ""
