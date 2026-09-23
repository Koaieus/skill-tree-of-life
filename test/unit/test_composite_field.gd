extends GutTest

## CompositeField: folds children via SUM / MAX / MUL.


func _const(v: float) -> ConstantField:
	var f := ConstantField.new()
	f.value = v
	return f


func test_empty_children_is_neutral() -> void:
	var f := CompositeField.new()
	assert_almost_eq(f.sample(Vector2.ZERO), 1.0, 0.0001)


func test_sum_mode() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.SUM
	f.children = [_const(2.0), _const(3.0)]
	assert_almost_eq(f.sample(Vector2.ZERO), 5.0, 0.0001)


func test_mul_mode() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.MUL
	f.children = [_const(2.0), _const(3.0)]
	assert_almost_eq(f.sample(Vector2.ZERO), 6.0, 0.0001)


func test_max_mode() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.MAX
	f.children = [_const(2.0), _const(5.0), _const(1.0)]
	assert_almost_eq(f.sample(Vector2.ZERO), 5.0, 0.0001)


func test_nested_composite() -> void:
	var inner := CompositeField.new()
	inner.mode = CompositeField.Mode.SUM
	inner.children = [_const(1.0), _const(1.0)]
	var outer := CompositeField.new()
	outer.mode = CompositeField.Mode.MUL
	outer.children = [inner, _const(3.0)]
	# inner = 2.0, outer = 2.0 * 3.0 = 6.0
	assert_almost_eq(outer.sample(Vector2.ZERO), 6.0, 0.0001)


func test_null_children_are_skipped() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.SUM
	f.children = [_const(2.0), null]
	assert_almost_eq(f.sample(Vector2.ZERO), 2.0, 0.0001)


# ── mask-radius back-fill through holders and composites (#557) ───────────
# A RadialGradientField with `outer_radius <= 0` opts into the resolved shape
# mask radius. Every ScalarField holder must reach it, at any nesting depth.


func _gradient(outer: float = 0.0) -> RadialGradientField:
	var g := RadialGradientField.new()
	g.outer_radius = outer
	return g


func _composite(kids: Array[ScalarField]) -> CompositeField:
	var c := CompositeField.new()
	c.children = kids
	return c


func _config_with(budget_field: ScalarField, placements: Array[Resource] = []) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.seed = 557
	cfg.topology.node_count = 30
	cfg.shape.shape_mask = CircularShapeMask.new()
	cfg.content.budget_policy = BudgetPolicy.new()
	cfg.content.budget_policy.budget_field = budget_field
	cfg.content.guaranteed_placements = placements
	return cfg


## Generates and returns the config generation RESOLVED — the fields the
## back-fill wrote live on it, not necessarily on the object passed in.
func _resolve(cfg: GraphProcgenConfig) -> GraphProcgenConfig:
	var graph: Graph = autofree((load("res://graph/graph.tscn") as PackedScene).instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	return result.get("config", cfg) as GraphProcgenConfig


func _mask_radius(cfg: GraphProcgenConfig) -> float:
	var aabb := cfg.shape.shape_mask.aabb()
	return 0.5 * minf(aabb.size.x, aabb.size.y)


func test_a_gradient_inside_a_composite_is_not_flat_after_generate() -> void:
	var resolved := await _resolve(_config_with(_composite([_gradient()])))
	var field: ScalarField = resolved.content.budget_policy.budget_field
	var r := _mask_radius(resolved)
	assert_gt(r, 0.0, "sanity: the mask resolved a radius")
	# An un-filled gradient (span clamped to 0.0001) is a step at the centre,
	# not a ramp: flat everywhere except the single centre point. So "not
	# flat" is asserted where it bites — halfway out must sit strictly
	# between the centre and rim multipliers.
	var centre := field.sample(Vector2.ZERO)
	var mid := field.sample(Vector2(0.5 * r, 0.0))
	var rim := field.sample(Vector2(r, 0.0))
	assert_ne(centre, rim, "the gradient has no range at all")
	assert_between(mid, minf(centre, rim) + 0.01, maxf(centre, rim) - 0.01,
			"halfway out samples a rim/centre value — the nested gradient was never back-filled, so it is flat")


func test_a_scene_placement_weight_gradient_is_back_filled() -> void:
	var placement := ScenePlacement.new()
	placement.weight = _gradient()
	var resolved := await _resolve(_config_with(null, [placement] as Array[Resource]))
	var got: RadialGradientField = (resolved.content.guaranteed_placements[0] as ScenePlacement).weight
	assert_almost_eq(got.outer_radius, _mask_radius(resolved), 0.001,
			"ScenePlacement.weight is a ScalarField holder the back-fill must visit")


func test_back_fill_recurses_through_nested_composites() -> void:
	var resolved := await _resolve(_config_with(_composite([_composite([_gradient()])])))
	var outer: CompositeField = resolved.content.budget_policy.budget_field
	var got: RadialGradientField = (outer.children[0] as CompositeField).children[0]
	assert_almost_eq(got.outer_radius, _mask_radius(resolved), 0.001,
			"a gradient two composites deep must be back-filled too")


func test_an_authored_outer_radius_is_never_overwritten() -> void:
	var placement := ScenePlacement.new()
	placement.weight = _composite([_gradient(111.0)])
	var cfg := _config_with(_composite([_gradient(222.0), _composite([_gradient(333.0)])]),
			[placement] as Array[Resource])
	var resolved := await _resolve(cfg)
	var bf: CompositeField = resolved.content.budget_policy.budget_field
	assert_eq((bf.children[0] as RadialGradientField).outer_radius, 222.0)
	assert_eq(((bf.children[1] as CompositeField).children[0] as RadialGradientField).outer_radius, 333.0)
	var w: CompositeField = (resolved.content.guaranteed_placements[0] as ScenePlacement).weight
	assert_eq((w.children[0] as RadialGradientField).outer_radius, 111.0)


func test_non_gradient_children_are_visited_and_left_alone() -> void:
	var resolved := await _resolve(_config_with(
			_composite([GaussianBumpField.new(), NoiseField.new(), _gradient()])))
	var bf: CompositeField = resolved.content.budget_policy.budget_field
	assert_almost_eq((bf.children[2] as RadialGradientField).outer_radius, _mask_radius(resolved), 0.001)
	assert_true(bf.children[0] is GaussianBumpField)
	assert_true(bf.children[1] is NoiseField)
