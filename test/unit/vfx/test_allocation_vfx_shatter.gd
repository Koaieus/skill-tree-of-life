extends GutTest

## #257 — AllocationVFX's node-death shatter: wiring onto #835's ShatterField
## in place of the old vibrate + particle-burst `_spawn_shatter`. The LOOK is
## judged under a real renderer (#838's live tab), not here — this pins the
## CPU-side contract: what gets pushed into the pool, and the pixel-parity
## constraint the shader's header cites (spawn tier pinned to INERT so the
## pre-flight crescendo isn't brighter than the live InnerDisk).

var _vfx: AllocationVFX


func before_each() -> void:
	_vfx = AllocationVFX.new()
	add_child_autofree(_vfx)


func test_shard_field_is_created_with_a_local_material() -> void:
	var field := _vfx.get_shard_field()
	assert_not_null(field)
	var mat := field.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.resource_local_to_scene,
			"a shared material would scrub every AllocationVFX's crescendo together")


func test_spawn_tier_defaults_pin_to_inert_for_pixel_parity() -> void:
	# The shader's own header explains why: anything above INERT would lift
	# the pre-flight crescendo brighter than the live InnerDisk's SDR tint,
	# breaking #257 acceptance 2 ("indistinguishable from the live node").
	assert_eq(_vfx.shatter_spawn_tier, Emissive.Tier.INERT)
	assert_eq(_vfx.shatter_end_tier, Emissive.Tier.INERT)
	assert_eq(_vfx.get_shard_field().spawn_tier, Emissive.Tier.INERT)


func test_tuning_exports_push_onto_the_field() -> void:
	_vfx.shatter_window = 2.0
	_vfx.shatter_flight_start = 0.4
	assert_almost_eq(_vfx.get_shard_field().window, 2.0, 0.0001)
	assert_almost_eq(_vfx.get_shard_field().flight_start, 0.4, 0.0001)


func test_process_advances_the_fields_own_elapsed_clock() -> void:
	var field := _vfx.get_shard_field()
	_vfx._process(0.5)
	assert_almost_eq(field.elapsed, 0.5, 0.0001)
	_vfx._process(0.25)
	assert_almost_eq(field.elapsed, 0.75, 0.0001)


func test_spawn_shatter_pools_shard_count_shards_with_delay_as_spawn_time() -> void:
	_vfx.shatter_shard_count = 6
	_vfx.shatter_fling_speed = 100.0
	var field := _vfx.get_shard_field()
	var before := field.used_slots()
	_vfx._spawn_shatter(Vector2(100.0, 50.0), 24.0, Color.CYAN, 0.7)
	assert_eq(field.used_slots() - before, 6)
	# Spawned before any _process tick, so `_shatter_clock` is still 0 — the
	# pushed spawn time is exactly the cascade `delay` handed in.
	for slot in range(before, field.used_slots()):
		assert_almost_eq(field.shard_spawn_time(slot), 0.7, 0.0001)


func test_spawn_shatter_gives_each_shard_only_its_radial_kick_no_inherited_momentum() -> void:
	_vfx.shatter_shard_count = 4
	_vfx.shatter_fling_speed = 140.0
	var field := _vfx.get_shard_field()
	var first: int = _vfx._spawn_shatter(Vector2.ZERO, 24.0, Color.WHITE, 0.0)
	for k in 4:
		var custom := field.shard_custom(first + k)
		var velocity := Vector2(custom.r, custom.g)
		var expected := ShatterField.radial_kick(k, 4, 140.0)
		assert_almost_eq(velocity, expected, Vector2.ONE * 0.01)
