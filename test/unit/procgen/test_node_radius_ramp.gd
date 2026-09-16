extends GutTest

## Acceptance for #783 — a generated node's `base_radius` is a function of its
## rolled budget, authored on a [NodeRadiusRamp] hand-built here (never the
## first_level `.tres`: the owner tunes, tests check the formula).


func _ramp() -> NodeRadiusRamp:
	var r := NodeRadiusRamp.new()
	r.min_radius = 28.0
	r.px_per_budget = 1.0
	r.knee_budget = 16
	r.cap = 50.0
	return r


func test_ramp_is_linear_below_the_knee() -> void:
	var r := _ramp()
	assert_almost_eq(r.radius_for(1), 28.0, 0.001)
	assert_almost_eq(r.radius_for(5), 32.0, 0.001)
	assert_almost_eq(r.radius_for(16), 43.0, 0.001)


func test_ramp_tail_is_continuous_monotone_and_below_cap() -> void:
	var r := _ramp()
	var prev := r.radius_for(16)
	for b in range(17, 200):
		var v := r.radius_for(b)
		assert_gt(v, prev, "budget %d must still grow" % b)
		assert_lt(v, r.cap, "budget %d must stay under the asymptote" % b)
		prev = v
	# Slope-1 at the knee: one unit past it grows by ~1px, not a jump.
	assert_almost_eq(r.radius_for(17) - r.radius_for(16), 1.0, 0.1)
	# An anomalous rim node (~28) stays legibly fatter than a plain rim 16.
	assert_gt(r.radius_for(28) - r.radius_for(16), 4.0)


func test_topology_without_ramp_is_uniform_and_budget_zero_is_the_default() -> void:
	var t := GraphProcgenTopology.new()
	t.node_radius = 32.0
	assert_almost_eq(t.radius_for_budget(7), 32.0, 0.001)
	assert_almost_eq(t.max_node_radius(), 32.0, 0.001)
	t.node_radius_ramp = _ramp()
	assert_almost_eq(t.radius_for_budget(0), 32.0, 0.001, "budget 0 is the golden default, not the ramp floor")
	assert_almost_eq(t.radius_for_budget(7), 34.0, 0.001)
	assert_almost_eq(t.max_node_radius(), 50.0, 0.001)


func _build_config(node_count: int, rng_seed: int) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.topology = GraphProcgenTopology.new()
	cfg.topology.node_count = node_count
	cfg.topology.node_radius = 32.0
	cfg.topology.node_padding = 50.0
	cfg.topology.node_radius_ramp = _ramp()
	cfg.seed = rng_seed
	cfg.shape = GraphProcgenShape.new()
	cfg.shape.shape_mask = CircularShapeMask.new()
	cfg.starting = GraphProcgenStartingPoints.new()
	cfg.content = GraphProcgenContent.new()
	var policy := ArchetypePolicy.new()
	policy.id = &"strength"
	policy.target_ratio = 1.0
	policy.archetype = load("res://archetypes/strength.tres")
	cfg.content.archetypes = [policy]
	# A wide range so the roll spreads across the linear band AND the tail.
	var bp := BudgetPolicy.new()
	bp.base_min = 1
	bp.base_max = 24
	cfg.content.budget_policy = bp
	cfg.blockers = GraphProcgenBlockers.new()
	cfg.blockers.blocker_per_small = 10
	cfg.blockers.blocker_per_medium = 25
	cfg.blockers.blocker_per_large = 100
	cfg.blockers.blocker_min_hops_from_core = 0
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Dictionary:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	return await GraphProcgen.generate(cfg, graph)


func test_generate_stamps_ramped_radius_and_constant_ring() -> void:
	var cfg := _build_config(60, 7831)
	# One keystone that authors its own radius: the stamp must win over the ramp.
	var ks := Keystone.new()
	ks.display_name = "Fat"
	ks.radius = 61.0
	var kp := KeystonePlacement.new()
	kp.keystone = ks
	kp.target_position = Vector2(200.0, 0.0)
	kp.exclude_starters = false
	cfg.content.guaranteed_placements = [kp]
	var result := await _generate(cfg)
	var nodes: Array = result["nodes"]
	assert_gt(nodes.size(), 0, "expected nodes")
	assert_gt((result.get("blockers", []) as Array).size(), 0, "expected blockers in the stamp check")
	var keystoned := 0
	var below_32 := 0
	var above_43 := 0
	for sn: SkillNode in nodes:
		# generate() deep-copies `content`, so match the keystone by name.
		if sn.keystone != null and sn.keystone.display_name == ks.display_name:
			keystoned += 1
			assert_almost_eq(sn.base_radius, 61.0, 0.001, "keystone radius wins over the ramp")
			continue
		var fp: Dictionary = sn.get_meta("procgen_footprint", {})
		assert_true(fp.has("budget"), "every node rolled a budget")
		var budget: int = fp["budget"]
		assert_gte(budget, 1)
		assert_almost_eq(sn.base_radius, cfg.topology.radius_for_budget(budget), 0.001,
				"base_radius follows the ramp for budget %d" % budget)
		assert_almost_eq(sn.base_inner_radius, sn.base_radius - 8.0, 0.001,
				"constant 8px ring")
		if sn.base_radius < 32.0:
			below_32 += 1
		if sn.base_radius > 43.0:
			above_43 += 1
	assert_eq(keystoned, 1, "the keystone landed on exactly one node")
	assert_gt(below_32, 0, "some node sits below the golden default")
	assert_gt(above_43, 0, "some node sits in the soft tail")


func test_min_dist_sizes_for_the_ramp_asymptote() -> void:
	var cfg := _build_config(80, 7832)
	cfg.topology.node_radius_ramp.cap = 50.0
	cfg.topology.node_padding = 50.0
	var result := await _generate(cfg)
	var nodes: Array = result["nodes"]
	assert_gt(nodes.size(), 0, "expected nodes")
	var min_dist := 2.0 * cfg.topology.max_node_radius() + cfg.topology.node_padding
	assert_almost_eq(min_dist, 150.0, 0.001)
	var closest := INF
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			closest = minf(closest, (nodes[i] as SkillNode).position.distance_to(
					(nodes[j] as SkillNode).position))
	assert_gte(closest, 150.0 - 0.001, "no two nodes closer than 2 * cap + padding")
	var mask := cfg.shape.shape_mask as CircularShapeMask
	var expected_r := sqrt(GraphProcgen.target_area_for_node_count(80, 150.0) / PI)
	assert_almost_eq(mask.radius, expected_r, 0.01, "mask sized from min_dist 150")
