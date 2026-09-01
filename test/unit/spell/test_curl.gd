extends GutTest

## [Curl] — the rotation system Cyclone's handedness is built on (#703).
##
## The graph is planar (procgen: Delaunay + prune only), so every vertex has a
## cyclic order of incident edges, and that order IS the handedness. These tests
## pin the three properties the spell leans on: the ordering is a real rotation,
## the arrival edge is never offered back, and nothing here reaches for `atan2`.

const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")


func _node(at: Vector2) -> SkillNode:
	var n := _SKILL_NODE.instantiate() as SkillNode
	n.position = at
	add_child_autofree(n)
	return n


func _names(nodes: Array[SkillNode]) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(n.position)
	return out


func test_pseudo_angle_is_monotone_in_the_true_angle() -> void:
	# Sampled around the full turn; the key must strictly increase with the
	# counter-clockwise angle. That monotonicity is the ONLY property the
	# comparator needs, which is what lets it replace a banned transcendental.
	var last := -INF
	for step in 32:
		var a := TAU * float(step) / 32.0
		var key := Curl.pseudo_angle(cos(a), sin(a))
		assert_gt(key, last, "pseudo_angle must increase with angle at %.2f rad" % a)
		last = key


func test_pseudo_angle_rejects_the_zero_vector() -> void:
	# A self-loop is a neighbour at zero distance — it has no angular slot at
	# all, and a naive `dx / (|dx| + |dy|)` would hand the sort a NaN.
	assert_eq(Curl.pseudo_angle(0.0, 0.0), -1.0, "no angular slot, and never NaN")


func test_rank_orders_neighbours_clockwise_from_the_arrival_edge() -> void:
	# Arriving at the origin from the west; neighbours at N, E, S. Turning
	# clockwise from "back towards the west" reaches S, then E, then N.
	var hub := _node(Vector2.ZERO)
	var north := _node(Vector2(0, -10))
	var east := _node(Vector2(10, 0))
	var south := _node(Vector2(0, 10))
	var cands: Array[SkillNode] = [north, east, south]
	var cw := Curl.rank(Vector2(-10, 0), hub, cands, true)
	assert_eq(_names(cw), [south.position, east.position, north.position])
	var ccw := Curl.rank(Vector2(-10, 0), hub, cands, false)
	assert_eq(_names(ccw), [north.position, east.position, south.position],
			"the other handedness is the exact reverse")


func test_rank_never_offers_the_arrival_edge_back() -> void:
	# This is why Cyclone dropped BacktrackFilter: a ranking measured FROM the
	# arrival edge cannot offer it, which is stronger than a filter can be for a
	# merged front carrying several predecessors.
	var hub := _node(Vector2.ZERO)
	var west := _node(Vector2(-10, 0))
	var east := _node(Vector2(10, 0))
	var cands: Array[SkillNode] = [west, east]
	var ranked := Curl.rank(west.position, hub, cands, true)
	assert_eq(ranked.size(), 1, "only the onward neighbour survives")
	assert_eq(ranked[0], east)


func test_rank_drops_a_self_loop() -> void:
	# Graph lists a self-looped node in its own adjacency (degree +2), so it
	# arrives as a candidate at zero distance. NoSelfLoopFilter stops traversal;
	# this stops it corrupting the SORT, which the filter never could.
	var hub := _node(Vector2.ZERO)
	var east := _node(Vector2(10, 0))
	var cands: Array[SkillNode] = [hub, east, hub]
	var ranked := Curl.rank(Vector2(-10, 0), hub, cands, true)
	assert_eq(ranked, [east] as Array[SkillNode])


func test_rank_survives_a_degenerate_arrival_position() -> void:
	# The seed measures from its cast-from node, which a sandbox can leave
	# stacked on top of it. Any fixed axis is fine; returning nothing is not.
	var hub := _node(Vector2.ZERO)
	var east := _node(Vector2(10, 0))
	var cands: Array[SkillNode] = [east]
	assert_eq(Curl.rank(hub.position, hub, cands, true).size(), 1)
