extends GutTest

## A Clamp weld brace dies with either edge it spans. A brace exists only to
## hold the angle between two edges incident to its joint; with either edge
## gone there is no angle left to hold, and a surviving brace would be a hidden
## second edge the `state.edges` reachability walk cannot see. Pins assert the
## CONSTRAINT SET, except the one live-sim pin, which asserts the outcome.

const _SPACING := 60.0
const _RADIUS := 24.0
const _DURATION := 1.2


func _chain(n: int) -> BladeState:
	var positions: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in n:
		positions.append(Vector2(float(i) * _SPACING, 0.0))
		radii.append(_RADIUS)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	return BladeState.build(positions, 0, edges, radii)


func _edge_index(state: BladeState, a: int, b: int) -> int:
	for i in state.edges.size():
		var e := state.edges[i]
		if (e.x == a and e.y == b) or (e.x == b and e.y == a):
			return i
	return -1


func _links(state: BladeState, a: int, b: int) -> bool:
	for c in state.constraints:
		var dc := c as BladeDistanceConstraint
		if dc == null:
			continue
		if (dc.a == a and dc.b == b) or (dc.a == b and dc.b == a):
			return true
	return false


func test_cutting_a_welded_edge_drops_the_brace_spanning_it() -> void:
	var s := _chain(3)
	ClampAddon.append_weld_braces(s, 1)
	assert_true(_links(s, 0, 2), "precondition: the weld at 1 braces 0-2")
	assert_true(s.remove_edge(_edge_index(s, 1, 2)))
	assert_false(_links(s, 0, 2), "no constraint may tie 0 to 2 once edge 1-2 is gone")
	assert_true(_links(s, 0, 1), "the surviving edge 0-1 keeps its own constraint")


func test_a_degree_3_joint_keeps_the_brace_between_its_surviving_edges() -> void:
	# Star: J = 1 joined to a = 2, b = 3, c = 0 (the pivot).
	var positions: Array[Vector2] = [
			Vector2.ZERO, Vector2(_SPACING, 0.0),
			Vector2(_SPACING * 2.0, 0.0), Vector2(_SPACING, _SPACING)]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(1, 3)]
	var radii: Array[float] = [_RADIUS, _RADIUS, _RADIUS, _RADIUS]
	var s := BladeState.build(positions, 0, edges, radii)
	ClampAddon.append_weld_braces(s, 1)
	assert_true(_links(s, 2, 3) and _links(s, 0, 2) and _links(s, 0, 3),
			"precondition: one brace per neighbour pair")
	s.remove_edge(_edge_index(s, 1, 2))
	assert_false(_links(s, 2, 3), "brace a-b spans the dead edge J-a")
	assert_false(_links(s, 0, 2), "brace a-c spans the dead edge J-a")
	assert_true(_links(s, 0, 3), "brace b-c holds the angle between two live edges")


func test_welds_either_side_of_a_cut_leave_nothing_bridging_it() -> void:
	var s := _chain(5)
	for j in [1, 2, 3]:
		ClampAddon.append_weld_braces(s, j)
	s.remove_edge(_edge_index(s, 1, 2))
	for inboard in [0, 1]:
		for outboard in [2, 3, 4]:
			assert_false(_links(s, inboard, outboard),
					"%d-%d bridges the cut at 1-2" % [inboard, outboard])
	assert_true(_links(s, 2, 4), "the weld at 3 lies wholly outboard and survives")


func test_a_brace_dies_with_its_joint() -> void:
	var s := _chain(3)
	ClampAddon.append_weld_braces(s, 1)
	s.remove_vertex(1)
	assert_false(_links(s, 0, 2), "a dead joint holds no angle")


func test_a_triangulated_joint_keeps_its_brace_when_the_far_edge_goes() -> void:
	# Triangle 0-1-2 welded at 1: the brace 0-2 duplicates edge 0-2. Cutting
	# 0-2 removes that edge's own constraint, not the brace — the angle at 1
	# is still there to hold.
	var positions: Array[Vector2] = [
			Vector2.ZERO, Vector2(_SPACING, 0.0), Vector2(_SPACING, _SPACING)]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(0, 2)]
	var radii: Array[float] = [_RADIUS, _RADIUS, _RADIUS]
	var s := BladeState.build(positions, 0, edges, radii)
	ClampAddon.append_weld_braces(s, 1)
	var before := s.constraints.size()
	s.remove_edge(_edge_index(s, 0, 2))
	assert_eq(s.constraints.size(), before - 1, "exactly one constraint goes")
	assert_true(_links(s, 0, 2), "the weld at 1 still braces 0-2")


func test_a_vertex_cut_off_a_weld_coasts_on_a_live_swing() -> void:
	var s := _chain(4)
	ClampAddon.append_weld_braces(s, 1)
	var pivot := s.positions[0]
	var offset := s.positions[1] - pivot
	var drivers: Array[BladeDriver] = [BladeArcDriver.new(
			1, pivot, offset.length(), offset.angle(), TAU, _DURATION)]
	var total := int(ceil(_DURATION / BladeSim.DEFAULT_DT))
	var cut_at := total / 4
	var head := BladeSim.simulate_range(s, drivers, 0, cut_at)
	s.positions = head.samples[head.samples.size() - 1].duplicate()
	s.prev_positions = head.prev_samples[head.prev_samples.size() - 1].duplicate()
	var r0 := s.positions[2].distance_to(pivot)
	s.remove_edge(_edge_index(s, 1, 2))
	var tail := BladeSim.simulate_range(s, drivers, cut_at, 10)
	var spread := 0.0
	for pose in tail.samples:
		spread = maxf(spread, absf(pose[2].distance_to(pivot) - r0))
	assert_gt(spread, 5.0,
			"vertex 2 must coast free of the pivot once edge 1-2 is cut, not stay pinned at %.1f" % r0)
