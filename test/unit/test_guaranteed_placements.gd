extends GutTest

## GuaranteedPlacement subtypes: RandomBudgetBoost + MinNearStartingPoints +
## TopologicalBudgetBump.


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# 10-node line graph 0-1-2-3-4-5-6-7-8-9.
func _line(n: int = 10) -> PlacementContext:
	var ctx := PlacementContext.new()
	ctx.positions = []
	for i in n:
		ctx.positions.append(Vector2(float(i), 0.0))
	ctx.edge_pairs = []
	for i in n - 1:
		ctx.edge_pairs.append(Vector2i(i, i + 1))
	var adj: Array[PackedInt32Array] = []
	for i in n:
		adj.append(PackedInt32Array())
	for e in ctx.edge_pairs:
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)
	ctx.adjacency = adj
	var rt: Array = []
	rt.resize(n)
	for i in n:
		rt[i] = [] as Array[StringName]
	ctx.role_tags = rt
	ctx.rng = _rng()
	return ctx


# ── RandomBudgetBoost ─────────────────────────────────────────────────────


func test_random_budget_boost_tags_exactly_count() -> void:
	var ctx := _line(20)
	var p := RandomBudgetBoost.new()
	p.count = 5
	p.role_tag = &"anomalous"
	p.exclude_starters = false
	p.apply(ctx)
	var tagged := 0
	for tags in ctx.role_tags:
		if &"anomalous" in tags:
			tagged += 1
	assert_eq(tagged, 5)


func test_random_budget_boost_excludes_starters() -> void:
	var ctx := _line(10)
	ctx.starter_indices = PackedInt32Array([0, 1, 2])
	var p := RandomBudgetBoost.new()
	p.count = 7  # only 7 non-starter nodes
	p.role_tag = &"anomalous"
	p.exclude_starters = true
	p.apply(ctx)
	# Starters shouldn't be tagged.
	for s in [0, 1, 2]:
		assert_false(&"anomalous" in ctx.role_tags[s], "starter %d wrongly tagged" % s)
	var tagged := 0
	for tags in ctx.role_tags:
		if &"anomalous" in tags:
			tagged += 1
	assert_eq(tagged, 7)


func test_random_budget_boost_zero_count_is_noop() -> void:
	var ctx := _line(10)
	var p := RandomBudgetBoost.new()
	p.count = 0
	p.apply(ctx)
	for tags in ctx.role_tags:
		assert_eq(tags.size(), 0)


# ── MinNearStartingPoints ─────────────────────────────────────────────────


func test_min_near_starting_points_tags_neighbour() -> void:
	var ctx := _line(10)
	ctx.starter_indices = PackedInt32Array([0])
	var p := MinNearStartingPoints.new()
	p.role_tag = &"xp_growth"
	p.count = 1
	p.max_hops = 3
	p.apply(ctx)
	# Some node in 0..3 should carry the tag (excluding 0 itself).
	var tagged := 0
	for i in range(1, 4):
		if &"xp_growth" in ctx.role_tags[i]:
			tagged += 1
	assert_eq(tagged, 1)


func test_min_near_starting_points_respects_existing_tag() -> void:
	var ctx := _line(10)
	ctx.starter_indices = PackedInt32Array([0])
	# Pre-stamp node 2 with the desired tag.
	ctx.add_role_tag(2, &"xp_growth")
	var p := MinNearStartingPoints.new()
	p.role_tag = &"xp_growth"
	p.count = 1
	p.max_hops = 3
	p.apply(ctx)
	# Only node 2 should carry it — already satisfies count = 1.
	var tagged := 0
	for i in range(1, 4):
		if &"xp_growth" in ctx.role_tags[i]:
			tagged += 1
	assert_eq(tagged, 1)


func test_min_near_starting_points_multiple_starters() -> void:
	var ctx := _line(10)
	ctx.starter_indices = PackedInt32Array([0, 9])
	var p := MinNearStartingPoints.new()
	p.role_tag = &"xp_growth"
	p.count = 1
	p.max_hops = 2
	p.apply(ctx)
	var near_start := 0
	for i in range(1, 3):
		if &"xp_growth" in ctx.role_tags[i]:
			near_start += 1
	var near_end := 0
	for i in range(7, 9):
		if &"xp_growth" in ctx.role_tags[i]:
			near_end += 1
	assert_eq(near_start, 1, "starter 0 should have a near-tag")
	assert_eq(near_end, 1, "starter 9 should have a near-tag")


# ── TopologicalBudgetBump ─────────────────────────────────────────────────


func test_topological_bump_stays_connected() -> void:
	# Two disjoint line segments 0-1-2-3-4 and 5-6-7-8-9 (no cross edges).
	var ctx := PlacementContext.new()
	ctx.positions = []
	for i in 10:
		ctx.positions.append(Vector2(float(i), 0.0))
	var adj: Array[PackedInt32Array] = []
	for i in 10:
		adj.append(PackedInt32Array())
	var pairs := [[0, 1], [1, 2], [2, 3], [3, 4], [5, 6], [6, 7], [7, 8], [8, 9]]
	for pair in pairs:
		adj[pair[0]].append(pair[1])
		adj[pair[1]].append(pair[0])
	ctx.adjacency = adj
	var rt: Array = []
	rt.resize(10)
	for i in 10:
		rt[i] = [] as Array[StringName]
	ctx.role_tags = rt
	ctx.rng = _rng()

	var p := TopologicalBudgetBump.new()
	p.role_tag = &"anomalous"
	p.seed_count = 1
	p.max_hops = 2
	p.exclude_starters = false
	p.apply(ctx)

	var tagged: Array[int] = []
	for i in 10:
		if &"anomalous" in ctx.role_tags[i]:
			tagged.append(i)
	assert_true(tagged.size() > 0, "expected at least the seed to be tagged")
	# Every tagged node must fall entirely within one segment — never both.
	var in_first := tagged.filter(func(i): return i <= 4)
	var in_second := tagged.filter(func(i): return i >= 5)
	assert_true(in_first.is_empty() or in_second.is_empty(), "bump jumped the gap between segments: %s" % [tagged])


func test_topological_bump_zero_seed_count_is_noop() -> void:
	var ctx := _line(10)
	var p := TopologicalBudgetBump.new()
	p.seed_count = 0
	p.role_tag = &"anomalous"
	p.apply(ctx)
	for tags in ctx.role_tags:
		assert_eq(tags.size(), 0)


func test_topological_bump_excludes_starters_by_default() -> void:
	var ctx := _line(10)
	ctx.starter_indices = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8])
	var p := TopologicalBudgetBump.new()
	p.role_tag = &"anomalous"
	p.seed_count = 1
	p.max_hops = 0
	p.apply(ctx)
	# Only node 9 is eligible as a seed; hop 0 tags only itself.
	assert_true(&"anomalous" in ctx.role_tags[9])
	for i in range(0, 9):
		assert_false(&"anomalous" in ctx.role_tags[i])
