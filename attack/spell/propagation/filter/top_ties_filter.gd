@tool
class_name TopTiesFilter
extends PropagationFilter

## Keeps only the candidates tying for first place on a [NodeRanker] —
## [constant Direction.HIGHEST] keeps every candidate scoring the max,
## [constant Direction.LOWEST] every candidate scoring the min.
##
## Set-level by nature: "is this candidate the best" is unanswerable without
## the rest of the set, so this overrides [method PropagationFilter.narrow]
## and derives [method allows] from it. Replaces the old `TopTiesPass`, which
## lived inside [TakeTopNStep] (#850).

enum Direction { HIGHEST, LOWEST }

@export var ranker: NodeRanker = null
@export var direction: Direction = Direction.HIGHEST


## DERIVED from [method narrow], not asserted: a set of one trivially ties for
## first place, so this is [code]true[/code] whenever the ranker can score at
## all — and it stays correct by construction if the set rule ever changes.
## The real gate is [method narrow], which is why
## [method CompositeFilter.narrow] chains `narrow` and not `allows`.
func allows(
		from: SkillNode,
		to: SkillNode,
		payload: CastSpell,
		ctx: PropagationContext) -> bool:
	return not narrow(from, [to] as Array[SkillNode], payload, ctx).is_empty()


func narrow(
		_from: SkillNode,
		candidates: Array[SkillNode],
		payload: CastSpell,
		ctx: PropagationContext) -> Array[SkillNode]:
	if candidates.is_empty() or ranker == null:
		return []

	var scores: Array[float] = []
	for c in candidates:
		scores.append(ranker.score(c, payload, ctx))

	var target: float = scores.max() if direction == Direction.HIGHEST else scores.min()

	var out: Array[SkillNode] = []
	for i in range(candidates.size()):
		if is_equal_approx(scores[i], target):
			out.append(candidates[i])
	return out


## Draft copy — #764 rewrites all stage copy into player words in one pass.
func get_description() -> String:
	var metric := ranker.get_description() if ranker != null else "rank"
	var word := "highest" if direction == Direction.HIGHEST else "lowest"
	return "Only into the neighbours tied for %s %s." % [word, metric]
