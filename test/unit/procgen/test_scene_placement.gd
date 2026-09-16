extends GutTest

## Acceptance for #330 — [ScenePlacement] writes an authored scene into
## [member PlacementContext.scenes] at min..max weighted positions, and
## [GraphProcgen] instantiates that scene as node `i`, pure.

const _BASE := preload("res://entity/keystone/keystone_skill_node.tscn")


class _StepField extends ScalarField:
	func sample(point: Vector2) -> float:
		return 1.0 if point.x >= 4.0 else 0.0


func _ctx(n: int) -> PlacementContext:
	var ctx := PlacementContext.new()
	for i in n:
		ctx.positions.append(Vector2(float(i), 0.0))
	var adj: Array[PackedInt32Array] = []
	for i in n:
		adj.append(PackedInt32Array())
	ctx.adjacency = adj
	var rt: Array = []
	rt.resize(n)
	for i in n:
		rt[i] = [] as Array[StringName]
	ctx.role_tags = rt
	var ks: Array = []
	ks.resize(n)
	ctx.keystones = ks
	var sc: Array = []
	sc.resize(n)
	ctx.scenes = sc
	ctx.rng = RandomNumberGenerator.new()
	ctx.scene_rng = RandomNumberGenerator.new()
	ctx.scene_rng.seed = 7
	return ctx


func _placement(lo: int, hi: int) -> ScenePlacement:
	var p := ScenePlacement.new()
	p.node_scene = _BASE
	p.min_count = lo
	p.max_count = hi
	p.exclude_starters = false
	return p


func _placed(ctx: PlacementContext) -> Array[int]:
	var out: Array[int] = []
	for i in ctx.scenes.size():
		if ctx.scenes[i] != null:
			out.append(i)
	return out


func test_places_exactly_count_copies_without_replacement() -> void:
	pending("#330")
	return
	var ctx := _ctx(10)
	_placement(3, 3).apply(ctx)
	assert_eq(_placed(ctx).size(), 3)
	for i in _placed(ctx):
		assert_eq(ctx.scenes[i], _BASE)
		assert_true(&"keystone" in ctx.role_tags[i])


func test_count_is_drawn_inclusive_between_min_and_max() -> void:
	pending("#330")
	return
	var seen := {}
	for seed in 40:
		var ctx := _ctx(10)
		ctx.scene_rng.seed = seed
		_placement(0, 2).apply(ctx)
		seen[_placed(ctx).size()] = true
	assert_eq(seen.keys().size(), 3, "0, 1 and 2 all occur across seeds")


func test_zero_weight_candidates_are_never_picked() -> void:
	pending("#330")
	return
	var ctx := _ctx(10)
	var p := _placement(5, 5)
	p.weight = _StepField.new()  # indices 0..3 sample to 0
	p.apply(ctx)
	assert_eq(_placed(ctx).size(), 5)
	for i in _placed(ctx):
		assert_gte(i, 4)


func test_starters_and_their_hop_ball_are_skipped() -> void:
	pending("#330")
	return
	var ctx := _ctx(10)
	ctx.starter_indices = PackedInt32Array([0])
	ctx.adjacency[0] = PackedInt32Array([1])
	ctx.adjacency[1] = PackedInt32Array([0, 2])
	ctx.adjacency[2] = PackedInt32Array([1])
	var p := _placement(7, 7)
	p.exclude_starters = true
	p.min_hops_from_starter = 2
	p.apply(ctx)
	assert_eq(_placed(ctx), [3, 4, 5, 6, 7, 8, 9] as Array[int])


func test_second_placement_never_overwrites_a_placed_scene() -> void:
	pending("#330")
	return
	var ctx := _ctx(4)
	_placement(4, 4).apply(ctx)
	var other := _placement(1, 1)
	other.node_scene = preload("res://skill_node/skill_node.tscn")
	other.apply(ctx)
	for i in 4:
		assert_eq(ctx.scenes[i], _BASE)


func test_draws_never_touch_the_main_rng_stream() -> void:
	pending("#330")
	return
	var ctx := _ctx(10)
	ctx.rng.seed = 123
	var before := ctx.rng.state
	_placement(2, 4).apply(ctx)
	assert_eq(ctx.rng.state, before)


func test_generate_instantiates_the_scene_as_node_i_pure() -> void:
	pending("#330")
	return
	# On a hand-built GraphProcgenConfig with one ScenePlacement (1/1) and a
	# non-empty archetype list: exactly one generated node is an instance of
	# the authored scene (scene_file_path == the scene's path); that node has
	# no archetype, empty `modifiers`, no addons, base_radius == the scene's
	# authored value (not topology.node_radius, not the ramp), and it is not
	# in the spell-grant pool nor a blocker.
	assert_true(false, "written by #330")
