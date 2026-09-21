@tool
class_name EuclideanRangeFinder
extends RangeFinder

## Straight-line scene-pixel distance from source to candidate.
##
## Reach rule (#944, owner): a candidate is in range when ANY PART of its
## hitbox lies within the reach circle drawn from the source's centre —
## `d - candidate.radius <= reach`. The source's own radius never counts
## (rim-to-rim was offered and not chosen). Consequence: stake-grown nodes
## are easier to reach. The reach circle [method get_visual] draws is thus
## exactly "a node whose hitbox touches this is in range".
##
## Hops-based finders are unaffected: they treat nodes as infinitesimal
## vertices. See [method _reaches] — the ONE spelling of this predicate.

@export var max_distance: float = 250.0


func in_range(attacker: Entity, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	return _reaches(_centre_distance(source, candidate), candidate, effective_distance(attacker, source))


## One linear scan: O(N) over whatever mirror is handed in, and that mirror is
## usually the WHOLE BOARD — [NodeTargeting] and [SpellTargetUnion] pass
## `graph.navigator` (800 nodes today, 2k–3k targeted), and ranged leaves reach
## 1500px+, so this is neither small nor cheap. A spatial/physics-backed scan
## (#945) would swap the iteration here and leave [method _reaches] alone.
## Reach stays unscaled whenever [param attacker] is `null` (every pre-#385
## caller) — see [method RangeFinder.gather].
##
## The stored value is the CENTRE distance `d`, not `d - radius`: it feeds
## [DistanceScale], which asked for no semantic change.
func gather(source: SkillNode, mirror: GraphMirror, attacker: Entity = null) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	var reach := max_distance if attacker == null else effective_distance(attacker, source)
	for n in mirror.get_mirrored_nodes():
		var d := _centre_distance(source, n)
		if _reaches(d, n, reach):
			out[n] = d
	return out


## ONE sweep of the node list for ALL sources, not one per source. The base
## implementation would run [method gather]'s full linear scan N times; here
## the widest source radius bounds a single pass, and each node is tested
## against only the sources whose reach could contain it.
##
## Radii are per-source by construction: `cast_range_distance` is node-local (a
## range-extender addon on the cast-from node moves that node's reach alone),
## so this is a union of DIFFERENT circles, not one circle N times.
func gather_multi(sources: Array[SkillNode], mirror: GraphMirror,
		attacker: Entity = null) -> Dictionary[SkillNode, Dictionary]:
	var out: Dictionary[SkillNode, Dictionary] = {}
	if mirror == null:
		return out
	var reaches: Dictionary[SkillNode, float] = {}
	var widest := 0.0
	for source in sources:
		if source == null:
			continue
		var reach := max_distance if attacker == null else effective_distance(attacker, source)
		reaches[source] = reach
		widest = max(widest, reach)
		out[source] = {} as Dictionary[SkillNode, float]
	if reaches.is_empty():
		return out
	for n in mirror.get_mirrored_nodes():
		for source: SkillNode in reaches:
			var d := _centre_distance(source, n)
			# Cheap reject first: nothing whose hitbox lies wholly past the
			# widest reach can be in range of ANY source, so the per-source
			# test costs nothing on a miss.
			if not _reaches(d, n, widest):
				continue
			if _reaches(d, n, reaches[source]):
				(out[source] as Dictionary[SkillNode, float])[n] = d
	return out


## The one reach predicate (#944): [param d] is the centre-to-centre distance
## from the source, and the candidate is in range when any part of its hitbox
## lies within [param reach]. Every caller above goes through here; a
## semantic change is a one-line edit.
static func _reaches(d: float, candidate: SkillNode, reach: float) -> bool:
	return d - candidate.radius <= reach


## The only centre-distance computation in this file — it both feeds
## [method _reaches] and is what [method gather] stores.
static func _centre_distance(source: SkillNode, candidate: SkillNode) -> float:
	return source.global_position.distance_to(candidate.global_position)


func max_reach() -> float:
	return max_distance


func get_visual(attacker: Entity, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	if source == null:
		return visual
	var dist := effective_distance(attacker, source)
	if dist <= 0.0:
		return visual
	visual.rings.append(RangeVisual.Ring.new(source.global_position, dist))
	return visual


## One ring per eligible caster, each at ITS OWN radius — `cast_range_distance` is
## node-local, so this is a union of different circles, not one circle drawn N
## times. Cheap by construction: a ring is a position and a float, no traversal.
func get_union_visual(attacker: Entity, union: SpellTargetUnion) -> RangeVisual:
	var visual := RangeVisual.new()
	if union == null:
		return visual
	for source in union.sources:
		if source == null:
			continue
		var dist := effective_distance(attacker, source)
		if dist <= 0.0:
			continue
		visual.rings.append(RangeVisual.Ring.new(source.global_position, dist))
	return visual


## Public for the same reason [method HopRangeFinder.effective_max_hops] is:
## [SpellTooltip] prints this number while hovering, and must ask for it rather
## than re-derive it. [param board] is its no-cast-from-node path.
func effective_distance(attacker: Entity, source: SkillNode, board: StatBoard = null) -> float:
	return SpellRangeRules.reach(&"cast_range_distance", max_distance, attacker, source, board)


## "Within N units", N being [method effective_distance] for [param board].
## See [method RangeFinder.get_description].
func get_description(board: StatBoard = null) -> String:
	var eff := effective_distance(null, null, board)
	return "Within %s units" % _fmt_num(eff)
