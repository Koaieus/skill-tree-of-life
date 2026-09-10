@tool
class_name TakeTopNSpread
extends PropagationSpread

## Sorts the eligible nodes with the configured [member ranker], takes the top
## [member take_count]. [member direction] picks max or min ranking. Stable
## tie-break (preserves scene order from [method Graph.get_neighbours]).
##
## Collapses the old HighestDegreePropagation + RankedStatPropagation into
## one shape parameterised by the ranker.
##
## Sorting and picking is ALL it does. Narrowing the candidate set first —
## "only those beating the current node", "only those tied for best" — is the
## filter's job: [RankThresholdFilter] and [TopTiesFilter], composed on
## [member PropagationConfig.filter]. This class used to carry a parallel
## `passes` chain that did the same thing one stage later; #850 deleted it.

enum Direction { HIGHEST, LOWEST }

@export var ranker: NodeRanker = null
@export var direction: Direction = Direction.HIGHEST
@export_range(1, 16) var take_count: int = 1


func select(
		_current: SkillNode,
		eligible: Array[SkillNode],
		payload: CastSpell,
		ctx: PropagationContext) -> Array[PropagationPick]:
	if eligible.is_empty() or ranker == null:
		return []

	var dir_sign := 1.0 if direction == Direction.LOWEST else -1.0
	var sorted := eligible.duplicate()
	sorted.sort_custom(func(a: SkillNode, b: SkillNode) -> bool:
		return dir_sign * ranker.score(a, payload, ctx) < dir_sign * ranker.score(b, payload, ctx))
	var k: int = min(take_count, sorted.size())
	var out: Array[PropagationPick] = []
	for i in k:
		out.append(PropagationPick.to(sorted[i]))
	return out


func get_description() -> String:
	var word := "highest" if direction == Direction.HIGHEST else "lowest"
	var metric := ranker.get_description() if ranker != null else "ranked"
	return "Chains to %d %s-%s neighbour(s)." % [take_count, word, metric]
