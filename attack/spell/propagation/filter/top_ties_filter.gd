@tool
class_name TopTiesFilter
extends PropagationFilter

## Keeps only the candidates tying for first place (or, with [member places]
## above 1, for any of the first few dense places) on a [NodeRanker] —
## [constant Direction.HIGHEST] keeps every candidate scoring the max,
## [constant Direction.LOWEST] every candidate scoring the min.
##
## Set-level by nature: "is this candidate the best" is unanswerable without
## the rest of the set, so this overrides [method PropagationFilter.narrow]
## and derives [method allows] from it. Replaces the old `TopTiesPass`, which
## lived inside [TakeTopNSpread] (#850).

enum Direction { HIGHEST, LOWEST }

@export var ranker: NodeRanker = null
@export var direction: Direction = Direction.HIGHEST
## How many distinct score places survive, dense-ranked: 2 keeps every
## candidate tied at first OR second place, dropping third and below.
@export_range(1, 5, 1, "or_greater") var places: int = 1


## DERIVED from [method narrow], not asserted: a set of one trivially ties for
## first place, so this is [code]true[/code] whenever the ranker can score at
## all — and it stays correct by construction if the set rule ever changes.
## The real gate is [method narrow], which is why
## [method CompositeFilter.narrow] chains `narrow` and not `allows`.
func allows(to: SkillNode, lctx: LandingContext) -> bool:
	return not narrow([to] as Array[SkillNode], lctx).is_empty()


func narrow(candidates: Array[SkillNode], lctx: LandingContext) -> Array[SkillNode]:
	if candidates.is_empty() or ranker == null:
		return []

	var scores: Array[float] = []
	for c in candidates:
		scores.append(ranker.score(c, lctx))

	# Dense ranking: the distinct scores, best first; the first `places` of
	# them survive, every candidate tied at one of them kept.
	var distinct: Array[float] = []
	for s in scores:
		if not distinct.any(func(d: float) -> bool: return is_equal_approx(d, s)):
			distinct.append(s)
	distinct.sort()
	if direction == Direction.HIGHEST:
		distinct.reverse()
	var kept := distinct.slice(0, maxi(places, 1))

	var out: Array[SkillNode] = []
	for i in range(candidates.size()):
		if kept.any(func(d: float) -> bool: return is_equal_approx(d, scores[i])):
			out.append(candidates[i])
	return out


func get_description() -> String:
	var metric := ranker.get_description() if ranker != null else "rank"
	var word := "highest" if direction == Direction.HIGHEST else "lowest"
	if places > 1:
		return "Only into nodes among the %d %s %s values." % [places, word, metric]
	return "Only into nodes tied for the %s %s." % [word, metric]
