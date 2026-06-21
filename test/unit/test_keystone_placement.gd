extends GutTest

## KeystonePlacement: nearest-to-target picks the right node, stamps the
## keystone reference + role tag, respects exclude_starters.


func _ctx(n: int) -> PlacementContext:
	var ctx := PlacementContext.new()
	# Linear positions x=0..n-1, all at y=0.
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
	ctx.rng = RandomNumberGenerator.new()
	return ctx


func _stat_keystone() -> StatKeystone:
	var ks := StatKeystone.new()
	ks.display_name = "Test"
	return ks


func test_places_on_nearest_node() -> void:
	var ctx := _ctx(10)
	var p := KeystonePlacement.new()
	p.keystone = _stat_keystone()
	p.target_position = Vector2(3.4, 0.0)  # closest to index 3
	p.exclude_starters = false
	p.apply(ctx)
	assert_eq(ctx.keystones[3], p.keystone)
	# Other slots null.
	for i in [0, 1, 2, 4, 5, 6, 7, 8, 9]:
		assert_null(ctx.keystones[i])


func test_stamps_role_tag() -> void:
	var ctx := _ctx(5)
	var p := KeystonePlacement.new()
	p.keystone = _stat_keystone()
	p.target_position = Vector2(2.0, 0.0)
	p.role_tag = &"keystone"
	p.exclude_starters = false
	p.apply(ctx)
	assert_true(&"keystone" in ctx.role_tags[2])


func test_exclude_starters_picks_next_nearest() -> void:
	var ctx := _ctx(10)
	ctx.starter_indices = PackedInt32Array([3])
	var p := KeystonePlacement.new()
	p.keystone = _stat_keystone()
	p.target_position = Vector2(3.0, 0.0)
	p.exclude_starters = true
	p.apply(ctx)
	# Should pick node 2 or 4 (both equidistant from 3); not 3.
	assert_null(ctx.keystones[3])
	var placed := -1
	for i in 10:
		if ctx.keystones[i] != null:
			placed = i
			break
	assert_true(placed == 2 or placed == 4, "expected 2 or 4 next-nearest, got %d" % placed)


func test_no_keystone_or_no_context_is_noop() -> void:
	var p := KeystonePlacement.new()
	# No keystone → silent noop.
	p.apply(_ctx(3))
	# No context → silent noop.
	p.keystone = _stat_keystone()
	p.apply(null)
	assert_true(true)
