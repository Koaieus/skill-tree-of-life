extends GutTest

## The acceptance gate for `tools/curl_spectrum/` (#705).
##
## [CurlOperator] is a measuring device, and a measuring device that drifts is
## worse than none — every #705 number about real procgen ground is only worth
## reading because the same operator reproduces the idealised table #703 tuned
## against. Table A of the snapshot is exactly these rows.
##
## It also pins [method Curl.rank] against [method Curl.rank_indices]: the
## shipped step calls the first, the operator calls the second, and the split
## only earns its keep while the two cannot disagree.

## `var`, not `const`: a PackedFloat32Array literal is not a constant expression.
static var _COEFFICIENTS := PackedFloat32Array([0.65, 0.45, 0.25])
## The table is quoted to three decimals; this is the last digit.
const _TOLERANCE := 0.0005

var _helper: SpellTestHelper


func before_each() -> void:
	_helper = SpellTestHelper.new()


func _rho(terrain: CurlTerrain) -> float:
	return CurlOperator.build(terrain).spectral_radius(_COEFFICIENTS)


func test_every_tree_is_exactly_zero() -> void:
	# Not "small": on a tree the walk is non-backtracking with nowhere to
	# rejoin, so the operator is nilpotent and the spell is seed + one decaying
	# fan. This is the row that makes the connectivity floor a real question.
	assert_eq(_rho(CurlLattices.path(6)), 0.0, "path")
	assert_eq(_rho(CurlLattices.star(5)), 0.0, "star")
	assert_eq(_rho(CurlLattices.binary_tree(4)), 0.0, "binary tree")


func test_a_lone_ring_reads_c1_regardless_of_length_or_parity() -> void:
	for n in [3, 4, 5, 6]:
		assert_almost_eq(_rho(CurlLattices.ring(n)), 0.650, _TOLERANCE, "ring-%d" % n)


func test_a_tail_on_a_ring_contributes_nothing() -> void:
	assert_almost_eq(_rho(CurlLattices.ring_with_tail(4, 5)), 0.650, _TOLERANCE)


func test_two_dimensional_terrain_reads_above_one() -> void:
	assert_almost_eq(_rho(CurlLattices.double_triangle()), 0.893, _TOLERANCE, "double triangle")
	assert_almost_eq(_rho(CurlLattices.wheel(6)), 1.159, _TOLERANCE, "hex wheel")
	assert_almost_eq(_rho(CurlLattices.triangular_lattice(2)), 1.296, _TOLERANCE, "19-node lattice")
	assert_almost_eq(_rho(CurlLattices.triangular_lattice(3)), 1.326, _TOLERANCE, "37-node lattice")


func test_shipped_coefficients_satisfy_the_authoring_condition() -> void:
	# c_1 < 1 < sum(c_r): a lone ring cannot sustain itself, a triangulated
	# patch can. The whole spell is this inequality.
	var shipped: PackedFloat32Array = SpectrumHarness.COEFFICIENT_SETS[SpectrumHarness.SHIPPED_LABEL]
	var total := 0.0
	for c in shipped:
		total += c
	assert_lt(shipped[0], 1.0, "c_1 below 1")
	assert_gt(total, 1.0, "sum above 1")
	assert_almost_eq(_rho(CurlLattices.ring(5)), 0.650, _TOLERANCE,
			"calibration set still reads the #703 table")


func test_rank_indices_agrees_with_the_shipped_rank() -> void:
	# A hub with four spokes: the front arrives from index 1 and the ranking has
	# to hand back the other three, sharpest clockwise turn first.
	var positions := {
		0: Vector2.ZERO,
		1: Vector2(-100.0, 0.0),
		2: Vector2(0.0, -100.0),
		3: Vector2(100.0, 0.0),
		4: Vector2(0.0, 100.0),
	}
	var graph := _helper.make_graph([[0, 1], [0, 2], [0, 3], [0, 4]], self, positions)
	var nodes := graph.get_skill_nodes()
	var candidates: Array[SkillNode] = [nodes[1], nodes[2], nodes[3], nodes[4]]
	var ranked := Curl.rank(nodes[1].global_position, nodes[0], candidates)
	var geometry := PackedVector2Array()
	for nb in candidates:
		geometry.append(nb.global_position)
	var indices := Curl.rank_indices(
			nodes[1].global_position, nodes[0].global_position, geometry)
	assert_eq(ranked.size(), indices.size(), "same fan width")
	for r in indices.size():
		assert_eq(ranked[r], candidates[indices[r]], "rank %d agrees" % r)
	assert_eq(ranked.size(), 3, "the arrival edge is dropped, never offered")


func test_a_territory_ball_is_a_connected_induced_subgraph() -> void:
	# Table C reads one holding, not the map — and a ball that quietly returned
	# a disconnected pile would report a ρ no cast could ever realise.
	var lattice := CurlLattices.triangular_lattice(3)
	var ball: CurlTerrain = lattice.bfs_ball(0, 12)["terrain"]
	assert_eq(ball.positions.size(), 12, "asked for 12 nodes")
	var seen := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var v: int = queue.pop_back()
		for nb in ball.adjacency[v]:
			if not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	assert_eq(seen.size(), 12, "and got one connected piece")


func test_wave_energies_decay_on_a_tree_and_grow_on_a_lattice() -> void:
	# The finite-horizon reading table D is built from, at both extremes.
	var tree := CurlLattices.binary_tree(5)
	var tree_op := CurlOperator.build(tree)
	var tree_waves := tree_op.wave_energies(1, 0, _COEFFICIENTS, 6)
	assert_lt(tree_waves[5], tree_waves[0], "a tree's last wave is weaker than its first")

	var lattice := CurlLattices.triangular_lattice(4)
	var lattice_op := CurlOperator.build(lattice)
	var centre := 0
	for i in lattice.positions.size():
		if lattice.degree(i) == 6:
			centre = i
			break
	var lattice_waves := lattice_op.wave_energies(
			lattice.adjacency[centre][0], centre, _COEFFICIENTS, 6)
	assert_gt(lattice_waves[5], lattice_waves[0], "a triangulated patch grows")
