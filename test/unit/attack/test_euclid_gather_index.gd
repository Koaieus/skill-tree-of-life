extends GutTest

## EuclideanRangeFinder on a real Graph rides the board's spatial index
## (`Graph.spatial_candidates`); a graph-less mirror takes the scan. The scan is
## the reference: both production paths must return the same set, the index
## must honour mirror membership, see a stake-grown radius without a rebuild,
## and examine a fraction of the board, not all of it.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _REACHES: Array[float] = [60.0, 250.0, 1500.0]

var _graph: Graph
var _finder: EuclideanRangeFinder


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate() as Graph
	add_child_autofree(_graph)
	_finder = EuclideanRangeFinder.new()


func _add(pos: Vector2, r: float) -> SkillNode:
	var n := _NODE_SCENE.instantiate() as SkillNode
	n.base_radius = r
	_graph.add_skill_node(n)
	n.global_position = pos
	return n


func _scatter(count: int) -> Array[SkillNode]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1701
	var nodes: Array[SkillNode] = []
	for i in count:
		nodes.append(_add(Vector2(rng.randf_range(0, 2400), rng.randf_range(0, 1600)),
				24.0 if rng.randi() % 2 == 0 else 32.0))
	_graph.navigator.reconcile()
	return nodes


func _bare_mirror(nodes: Array[SkillNode]) -> GraphMirror:
	var m := GraphMirror.new()
	autofree(m)
	for n in nodes:
		m.mirror_add(n)
	return m


func _sources(nodes: Array[SkillNode]) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for i in 8:
		out.append(nodes[(i * 7 + 3) % nodes.size()])
	return out


func _keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return a.get_instance_id() < b.get_instance_id())
	return k


func test_index_path_matches_the_scan_fallback() -> void:
	var nodes := _scatter(60)
	var bare := _bare_mirror(nodes)
	var srcs := _sources(nodes)
	for reach in _REACHES:
		_finder.max_distance = reach
		for s in srcs:
			var via_index := _finder.gather(s, _graph.navigator)
			var via_scan := _finder.gather(s, bare)
			assert_eq(_keys(via_index), _keys(via_scan), "gather, reach %d from %s" % [int(reach), s.global_position])
			for n in via_index:
				assert_eq(via_index[n], via_scan[n], "stored centre distance agrees")
		var multi_index := _finder.gather_multi(srcs, _graph.navigator)
		var multi_scan := _finder.gather_multi(srcs, bare)
		assert_eq(multi_index.size(), multi_scan.size())
		for s in srcs:
			assert_eq(_keys(multi_index[s]), _keys(multi_scan[s]), "gather_multi, reach %d" % int(reach))


func test_index_path_honours_mirror_membership() -> void:
	var nodes := _scatter(60)
	var half: Array[SkillNode] = []
	for i in nodes.size():
		if i % 2 == 0:
			half.append(nodes[i])
	var subset := GraphMirror.new()
	autofree(subset)
	subset.graph = _graph
	for n in half:
		subset.mirror_add(n)
	var bare_half := _bare_mirror(half)
	for reach in _REACHES:
		_finder.max_distance = reach
		for s in _sources(nodes):
			var got := _finder.gather(s, subset)
			for n in got:
				assert_true(half.has(n), "only members are gathered")
			assert_eq(_keys(got), _keys(_finder.gather(s, bare_half)),
					"exactly the members the scan returns, reach %d" % int(reach))


func test_stake_growth_is_seen_without_a_rebuild() -> void:
	# Tight cells so the margin, not cell slack, decides: the grower's centre
	# sits one cell past `reach + 24` and only its grown hitbox touches.
	_graph.spatial_cell_px = 32.0
	var reach := 100.0
	var source := _add(Vector2.ZERO, 24.0)
	var grower := _add(Vector2(reach + 29.0, 0.0), 24.0)
	_add(Vector2(2000, 2000), 24.0)
	_graph.navigator.reconcile()
	_finder.max_distance = reach
	assert_false(_finder.gather(source, _graph.navigator).has(grower), "precondition: out at base radius")
	grower.stake_level = 3
	assert_gt(grower.radius, 29.0, "precondition: the stake step grew the hitbox past the gap")
	assert_true(_finder.gather(source, _graph.navigator).has(grower),
			"a stake-grown node is gathered with no container change in between")


func test_candidates_are_a_fraction_of_the_board() -> void:
	for y in 20:
		for x in 20:
			_add(Vector2(x * 100.0, y * 100.0), 24.0)
	@warning_ignore("integer_division")
	var bound := 400 / 4
	for centre: Vector2 in [Vector2(950, 950), Vector2(1000, 1000), Vector2(0, 0), Vector2(1900, 1100)]:
		var cands := _graph.spatial_candidates(centre, 150.0)
		assert_gt(cands.size(), 0)
		assert_lt(cands.size(), bound, "a 150 px query at %s examines a fraction of N, not N" % centre)
