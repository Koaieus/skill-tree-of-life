extends GutTest

## SkillNodeGrid — the board's candidate index for reach gathers. It only
## narrows: `candidates_within` must be a SUPERSET of the exact hitbox-touching
## set (`EuclideanRangeFinder._reaches`), never miss a node that touches.

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _CELL := 128.0


func _node_at(pos: Vector2, r: float = 32.0) -> SkillNode:
	var n := _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(n)
	n.base_radius = r
	n.global_position = pos
	return n


## Exact set by the shipped predicate, as a brute-force reference.
func _exact(nodes: Array[SkillNode], centre: Vector2, reach: float) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for n in nodes:
		if EuclideanRangeFinder._reaches(centre.distance_to(n.global_position), n, reach):
			out.append(n)
	return out


func _assert_superset(cands: Array[SkillNode], exact: Array[SkillNode], what: String) -> void:
	for n in exact:
		assert_true(cands.has(n), "%s: %s touches the reach circle but is no candidate" % [what, n.global_position])


func _scatter() -> Array[SkillNode]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1701
	var nodes: Array[SkillNode] = []
	for i in 40:
		nodes.append(_node_at(Vector2(rng.randf_range(-900, 900), rng.randf_range(-600, 600)),
				24.0 if i % 2 == 0 else 32.0))
	return nodes


func test_candidates_are_a_superset_of_the_exact_set_for_every_reach() -> void:
	var nodes := _scatter()
	var grid := SkillNodeGrid.new()
	grid.rebuild(nodes, _CELL)
	assert_false(grid.is_empty())
	for reach: float in [0.0, 150.0, 5000.0]:
		for centre: Vector2 in [Vector2.ZERO, Vector2(500, -300), Vector2(-850, 580)]:
			var exact := _exact(nodes, centre, reach)
			_assert_superset(grid.candidates_within(centre, reach), exact,
					"reach %d at %s" % [int(reach), centre])
		if reach == 5000.0:
			assert_eq(grid.candidates_within(Vector2.ZERO, reach).size(), nodes.size(),
					"a reach past the span sees every node")


func test_boundary_rim_through_the_index() -> void:
	var reach := 100.0
	var r := 32.0
	var on_rim := _node_at(Vector2(reach + r, 0), r)
	var past_rim := _node_at(Vector2(0, -(reach + r + 1.0)), r)
	var far := _node_at(Vector2(2000, 2000), r)
	var grid := SkillNodeGrid.new()
	grid.rebuild([on_rim, past_rim, far] as Array[SkillNode], _CELL)
	var cands := grid.candidates_within(Vector2.ZERO, reach)
	assert_true(cands.has(on_rim), "centre at reach + r touches: a candidate")
	assert_false(cands.has(far), "a node many cells away is not examined")
	assert_eq(_exact([on_rim, past_rim] as Array[SkillNode], Vector2.ZERO, reach), [on_rim] as Array[SkillNode],
			"the predicate still rejects reach + r + 1")


func test_note_radius_widens_but_never_narrows_the_margin() -> void:
	var reach := 100.0
	# Base radius 24 at the build; the node then grows to 60 (a stake step).
	var grower := _node_at(Vector2(reach + 50.0, 0), 24.0)
	var anchor := _node_at(Vector2(1500, 1500), 24.0)
	var grid := SkillNodeGrid.new()
	grid.rebuild([grower, anchor] as Array[SkillNode], 16.0)
	assert_eq(grid.max_radius, 24.0, "max_radius is exact at build")
	grower.base_radius = 60.0
	grid.note_radius(60.0)
	assert_eq(grid.max_radius, 60.0)
	assert_true(grid.candidates_within(Vector2.ZERO, reach).has(grower),
			"a node that only touches under the bigger radius is a candidate after note_radius")
	grid.note_radius(10.0)
	assert_eq(grid.max_radius, 60.0, "note_radius never lowers the margin")


func test_empty_rebuild() -> void:
	var grid := SkillNodeGrid.new()
	grid.rebuild([] as Array[SkillNode], _CELL)
	assert_true(grid.is_empty())
	assert_eq(grid.candidates_within(Vector2.ZERO, 1000.0).size(), 0)


func test_cells_per_axis_cap_holds_on_a_huge_span() -> void:
	var a := _node_at(Vector2.ZERO, 24.0)
	var b := _node_at(Vector2(_CELL * 10000.0, _CELL * 10000.0), 24.0)
	var c := _node_at(Vector2(_CELL * 5000.0, 10.0), 24.0)
	var nodes: Array[SkillNode] = [a, b, c]
	var grid := SkillNodeGrid.new()
	grid.rebuild(nodes, _CELL)
	assert_lte(grid.cols, SkillNodeGrid.MAX_CELLS_PER_AXIS)
	assert_lte(grid.rows, SkillNodeGrid.MAX_CELLS_PER_AXIS)
	for centre: Vector2 in [Vector2.ZERO, b.global_position, c.global_position]:
		_assert_superset(grid.candidates_within(centre, 300.0), _exact(nodes, centre, 300.0),
				"capped grid at %s" % centre)
