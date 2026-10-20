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


## Every node of [param mirror] whose hitbox touches the source's reach circle,
## mapped to its centre distance. Reach stays unscaled whenever [param attacker]
## is `null` (every pre-#385 caller) — see [method RangeFinder.gather]. The
## entry a rider calls once per key; it delegates to [method gather_reach].
##
## The stored value is the CENTRE distance `d`, not `d - radius`: it feeds
## [DistanceScale], which asked for no semantic change.
func gather(source: SkillNode, mirror: GraphMirror, attacker: Entity = null) -> Dictionary[SkillNode, float]:
	if source == null or mirror == null:
		return {} as Dictionary[SkillNode, float]
	var reach := max_distance if attacker == null else effective_distance(attacker, source)
	return gather_reach(source, mirror, reach)


## [method gather] for a reach the caller supplies (a splash sized by the
## struck node's own stat). Candidates come from the board's spatial index,
## [method Graph.spatial_candidates], when [param mirror] has a `graph` — a
## cell walk, not a board walk — and each is kept only if the mirror holds it
## (`vertex_id >= 0`: an owned-mirror aura or a shadow-world mirror sees its
## members only). A graph-less mirror (a bare unit fixture) falls back to a
## scan of its own nodes. Either way [method _reaches] decides, so the index
## can only narrow. No result order is promised; a consumer that needs one
## sorts.
func gather_reach(source: SkillNode, mirror: GraphMirror, reach: float) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	if mirror.graph != null:
		for n in mirror.graph.spatial_candidates(source.global_position, reach):
			if mirror.vertex_id(n) < 0:
				continue
			var d := _centre_distance(source, n)
			if _reaches(d, n, reach):
				out[n] = d
		return out
	for n in mirror.get_mirrored_nodes():
		var d := _centre_distance(source, n)
		if _reaches(d, n, reach):
			out[n] = d
	return out


## One [method gather_reach] per source, each with its own reach: with the
## index each source is a small cell walk, so there is no shared sweep left to
## amortise.
##
## Radii are per-source by construction: `cast_range_distance` is node-local (a
## range-extender addon on the cast-from node moves that node's reach alone),
## so this is a union of DIFFERENT circles, not one circle N times.
func gather_multi(sources: Array[SkillNode], mirror: GraphMirror,
		attacker: Entity = null) -> Dictionary[SkillNode, Dictionary]:
	var out: Dictionary[SkillNode, Dictionary] = {}
	if mirror == null:
		return out
	for source in sources:
		if source == null:
			continue
		var reach := max_distance if attacker == null else effective_distance(attacker, source)
		out[source] = gather_reach(source, mirror, reach)
	return out


## Every node of [param nodes] whose hitbox touches a circle of [param reach]
## around [param source], [param source] itself excluded, in the given order.
## The per-call-radius entry for a caller with no attacker-scaled reach of its
## own (a blast sized by fuel); same [method _reaches] test, a linear scan of
## the supplied list (no mirror, so no index).
static func nodes_within(source: SkillNode, nodes: Array[SkillNode], reach: float) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if source == null:
		return out
	for n in nodes:
		if n != source and _reaches(_centre_distance(source, n), n, reach):
			out.append(n)
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
	return "Within %s units" % NumFmt.num(eff)
