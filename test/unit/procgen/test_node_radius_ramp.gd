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
	pending("#783")
	return
	var r := _ramp()
	assert_almost_eq(r.radius_for(1), 28.0, 0.001)
	assert_almost_eq(r.radius_for(5), 32.0, 0.001)
	assert_almost_eq(r.radius_for(16), 43.0, 0.001)


func test_ramp_tail_is_continuous_monotone_and_below_cap() -> void:
	pending("#783")
	return
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
	pending("#783")
	return
	var t := GraphProcgenTopology.new()
	t.node_radius = 32.0
	assert_almost_eq(t.radius_for_budget(7), 32.0, 0.001)
	assert_almost_eq(t.max_node_radius(), 32.0, 0.001)
	t.node_radius_ramp = _ramp()
	assert_almost_eq(t.radius_for_budget(0), 32.0, 0.001, "budget 0 is the golden default, not the ramp floor")
	assert_almost_eq(t.radius_for_budget(7), 34.0, 0.001)
	assert_almost_eq(t.max_node_radius(), 50.0, 0.001)


func test_generate_stamps_ramped_radius_and_constant_ring() -> void:
	pending("#783")
	return
	# Build a small config with a hand-built ramp + budget policy, generate,
	# and for every node assert:
	#   base_radius == topology.radius_for_budget(footprint.budget)
	#   base_inner_radius == base_radius - 8
	#   blockers included; a node stamped by a keystone with radius > 0 keeps it
	pass


func test_min_dist_sizes_for_the_ramp_asymptote() -> void:
	pending("#783")
	return
	# generate() with ramp cap 50 and node_padding 50: no two nodes closer than
	# 150 = 2 * max_node_radius() + node_padding, and the auto-scaled mask area
	# equals GraphProcgen.target_area_for_node_count(node_count, 150).
	pass
