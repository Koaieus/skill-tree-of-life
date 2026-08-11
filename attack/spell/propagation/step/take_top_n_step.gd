@tool
class_name TakeTopNStep
extends PropagationStep

## Sorts the candidates with the configured [member ranker], takes the top
## [member take_count]. [member direction] picks max or min ranking. Stable
## tie-break (preserves scene order from [method Graph.get_neighbours]).
##
## Collapses the old HighestDegreePropagation + RankedStatPropagation into
## one shape parameterised by the ranker.
##
## [member passes] is an ordered chain of [RankPass] reductions applied
## before sorting — each pass narrows the candidate set
## (e.g. [CurrentThresholdPass] → [TopTiesPass]).

enum Direction { HIGHEST, LOWEST }

@export var ranker: NodeRanker = null
@export var direction: Direction = Direction.HIGHEST
@export_range(1, 16) var take_count: int = 1
@export var passes: Array[RankPass] = []


func step(
		_current: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		ctx: PropagationContext) -> Array[CastSpell]:
	if candidates.is_empty() or ranker == null:
		return []

	var eligible: Array[SkillNode] = candidates
	for rp in passes:
		if rp == null:
			continue
		eligible = rp.filter(eligible, ranker, payload, ctx, _current, direction)
		if eligible.is_empty():
			return []

	var sign := 1.0 if direction == Direction.LOWEST else -1.0
	var sorted := eligible.duplicate()
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
	var parts := "Chains to %d %s-%s neighbour(s)" % [take_count, word, metric]
	if not passes.is_empty():
		var descs: Array[String] = []
		for rp in passes:
			if rp != null:
				var d := rp.get_description()
				if not d.is_empty():
					descs.append(d)
		if not descs.is_empty():
			parts += " [" + " → ".join(descs) + "]"
	return parts + "."
