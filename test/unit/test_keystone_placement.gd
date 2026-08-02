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


func _stat_keystone() -> Keystone:
	var ks := Keystone.new()
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


func test_no_keystone_is_noop() -> void:
	var ctx := _ctx(3)
	var p := KeystonePlacement.new()
	p.target_position = Vector2(1.0, 0.0)
	p.role_tag = &"keystone"
	# No keystone assigned → must place nothing AND stamp no tag, rather than
	# writing a null into the slot it would otherwise have picked.
	p.apply(ctx)
	for i in 3:
		assert_null(ctx.keystones[i], "slot %d must stay empty" % i)
		assert_eq(ctx.role_tags[i].size(), 0, "slot %d must not be tagged" % i)


func test_no_context_is_noop() -> void:
	var p := KeystonePlacement.new()
	p.keystone = _stat_keystone()
	# Passing a null context must return silently, not push an error or crash.
	# `assert_no_new_orphans` is not the point here — the observable contract is
	# that the call itself is survivable, so the following assert is what proves
	# control returned at all.
	p.apply(null)
	assert_not_null(p.keystone, "apply(null) must leave the placement itself untouched")
