@tool
class_name EuclideanRangeFinder
extends RangeFinder

## Straight-line scene-pixel distance from source to candidate.

@export var max_distance: float = 250.0


func in_range(attacker: Entity, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	return source.global_position.distance_to(candidate.global_position) <= effective_distance(attacker, source)


## One linear scan. Deliberately not a spatial index: an aura recompute runs on
## allocation events over a tens-of-nodes owned subgraph, not per frame over the
## whole graph (which is what earns VisionSystem its index). Reach stays
## unscaled whenever [param attacker] is `null` (every pre-#385 caller) — see
## [method RangeFinder.gather].
func gather(source: SkillNode, mirror: GraphMirror, attacker: Entity = null) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	var reach := max_distance if attacker == null else effective_distance(attacker, source)
	for n in mirror.get_mirrored_nodes():
		var d := source.global_position.distance_to(n.global_position)
		if d <= reach:
			out[n] = d
	return out


## ONE sweep of the node list for ALL sources, not one per source. The base
## implementation would run [method gather]'s full linear scan N times; here
## the widest source radius bounds a single pass, and each node is tested
## against only the sources whose reach could contain it.
##
## Radii are per-source by construction: `spell_range` is node-local (a
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
			var d := source.global_position.distance_to(n.global_position)
			# Cheap reject first: nothing further than the widest radius can be
			# in reach of ANY source, so the inner test costs nothing on a miss.
			if d > widest:
				continue
			if d <= reaches[source]:
				(out[source] as Dictionary[SkillNode, float])[n] = d
	return out


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


## One ring per eligible caster, each at ITS OWN radius — `spell_range` is
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
	return max_distance * spell_range_multiplier(attacker, source, board)
