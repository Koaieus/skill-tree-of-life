@tool
class_name TakeTopNStep
extends PropagationStep

## Sorts the candidates with the configured [member ranker], takes the top
## [member take_count]. [member direction] picks max or min ranking. Stable
## tie-break (preserves scene order from [method Graph.get_neighbours]).
##
## Collapses the old HighestDegreePropagation + RankedStatPropagation into
## one shape parameterised by the ranker.

enum Direction { HIGHEST, LOWEST }

@export var ranker: NodeRanker = null
@export var direction: Direction = Direction.HIGHEST
@export_range(1, 16) var take_count: int = 1


func step(
		_current: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		ctx: PropagationContext) -> Array[CastSpell]:
	if candidates.is_empty() or ranker == null:
		return []
	var sign := 1.0 if direction == Direction.LOWEST else -1.0
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: SkillNode, b: SkillNode) -> bool:
		return sign * ranker.score(a, payload, ctx) < sign * ranker.score(b, payload, ctx))
	var k: int = min(take_count, sorted.size())
	var out: Array[CastSpell] = []
	for i in k:
		out.append(_propagate_to(sorted[i], payload, config))
	return out


func get_description() -> String:
	var word := "highest" if direction == Direction.HIGHEST else "lowest"
	var metric := ranker.get_description() if ranker != null else "ranked"
	return "Chains to %d %s-%s neighbour(s)." % [take_count, word, metric]
