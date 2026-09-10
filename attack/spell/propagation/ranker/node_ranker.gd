@tool
@abstract
class_name NodeRanker
extends Resource

## Scores a candidate node for [TakeTopNSpread]. Subclasses pick the metric
## (degree, stat value, distance to core, …). Higher scores rank first;
## [TakeTopNSpread] flips the comparison via its [code]direction[/code] enum.


@abstract func score(node: SkillNode, payload: CastSpell, ctx: PropagationContext) -> float


func get_description() -> String:
	return ""
