extends GutTest

## #835 — `ShatterField`: the pooled, scrub-driven shard field both blade pops
## (#787) and node deaths (#257) fragment into.
##
## Headless Godot never reads a MultiMesh's per-instance buffer back
## (`docs/domain/rendering-performance.md`), so every "what got pushed" assert
## below reads the field's own CPU mirrors (`shard_transform` / `shard_color` /
## `shard_custom`) — the same pattern `Edge.render_*` uses. The motion curve the
## shader integrates is pinned through the static reference functions the
## include is documented to match (`shatter_motion.gdshaderinc`'s header).

const FIELD := preload("res://ui/vfx/shatter/shatter_field.tscn")

const WINDOW := 0.25
const TINT := Color(0.9, 0.3, 0.2, 1.0)
const V := Vector2(120.0, -40.0)


func _field(p0: float = 0.0) -> ShatterField:
	var field: ShatterField = FIELD.instantiate()
	field.window = WINDOW
	field.flight_start = p0
	add_child_autofree(field)
	return field


func _snapshot(field: ShatterField) -> Array:
	var out: Array = []
	for slot in field.used_slots():
		out.append([field.shard_transform(slot), field.shard_color(slot), field.shard_custom(slot)])
	return out


# ------------------------------------------------------- the motion contract


func test_progress_zero_displaces_nothing_and_progress_one_is_fully_faded() -> void:
	assert_eq(ShatterField.displacement_at(V, 0.0, WINDOW, 0.0), Vector2.ZERO)
	assert_almost_eq(ShatterField.fade_alpha_at(0.0, 0.0), 1.0, 0.0001)
	assert_eq(ShatterField.fade_alpha_at(1.0, 0.0), 0.0)
	assert_eq(ShatterField.fade_alpha_at(1.0, 0.6), 0.0)


func test_displacement_is_momentum_times_time_elapsed_with_no_drag() -> void:
	# Immediate pop (#787): flight spans the whole window.
	assert_almost_eq(ShatterField.displacement_at(V, 0.5, WINDOW, 0.0), V * 0.125, Vector2.ONE * 0.0001)
	assert_almost_eq(ShatterField.displacement_at(V, 1.0, WINDOW, 0.0), V * WINDOW, Vector2.ONE * 0.0001)
	# Crescendo first (#257): nothing moves before p0, then momentum x time since p0.
	assert_eq(ShatterField.displacement_at(V, 0.5, WINDOW, 0.6), Vector2.ZERO)
	assert_almost_eq(ShatterField.displacement_at(V, 0.9, WINDOW, 0.6), V * (0.3 * WINDOW), Vector2.ONE * 0.0001)
	# Linear in time: twice the progress past p0 is exactly twice the travel.
	var a := ShatterField.displacement_at(V, 0.7, WINDOW, 0.6)
	var b := ShatterField.displacement_at(V, 0.8, WINDOW, 0.6)
	assert_almost_eq(b, a * 2.0, Vector2.ONE * 0.0001)


func test_progress_is_elapsed_since_spawn_over_the_window() -> void:
	assert_almost_eq(ShatterField.progress_at(1.0, 1.0, WINDOW), 0.0, 0.0001)
	assert_almost_eq(ShatterField.progress_at(1.0, 1.125, WINDOW), 0.5, 0.0001)
	assert_almost_eq(ShatterField.progress_at(1.0, 9.0, WINDOW), 1.0, 0.0001)
	assert_almost_eq(ShatterField.progress_at(1.0, 0.5, WINDOW), 0.0, 0.0001)


func test_shard_velocity_is_seed_momentum_plus_its_own_radial_kick() -> void:
	var n := 8
	var sum := Vector2.ZERO
	for k in n:
		var kick := ShatterField.radial_kick(k, n, 50.0)
		assert_almost_eq(kick.length(), 50.0, 0.0001, "kick %d has the authored speed" % k)
		sum += kick
		assert_almost_eq(ShatterField.shard_velocity(V, k, n, 50.0), V + kick, Vector2.ONE * 0.0001)
	assert_almost_eq(sum, Vector2.ZERO, Vector2.ONE * 0.0001, "kicks are outward and symmetric")
	assert_eq(ShatterField.radial_kick(0, n, 50.0), Vector2(50.0, 0.0), "cell 0 sits on +x")
	assert_eq(ShatterField.shard_velocity(V, 3, n, 0.0), V, "no kick => pure momentum")


func test_shard_packing_round_trips_and_stays_exact_in_a_half_float() -> void:
	for probe in [Vector2i(0, 1), Vector2i(7, 8), Vector2i(31, 32)]:
		var packed := ShatterField.pack_shard(probe.x, probe.y)
		assert_eq(ShatterField.unpack_shard(packed), probe)
		# The compatibility renderer stores custom data as 16-bit halves; every
		# integer up to 2048 survives that, and nothing packed here exceeds it.
		assert_true(packed < 2048.0, "%s packs under the half-float integer limit" % probe)
		assert_eq(packed, floorf(packed))
	# Out-of-range inputs are clamped, never allowed to alias another shard.
	assert_eq(ShatterField.unpack_shard(ShatterField.pack_shard(40, 99)), Vector2i(31, 32))


# ------------------------------------------------------------- what is pushed


func test_spawn_pushes_a_tier_lifted_tint_and_momentum_per_shard() -> void:
	var field := _field()
	var origin := Vector2(300.0, 200.0)
	var first := field.spawn_shatter(origin, 24.0, TINT, V, 0.5, 8, 30.0)
	assert_eq(first, 0)
	assert_eq(field.used_slots(), 8)
	var lifted := Emissive.at(TINT, Emissive.VALUE)
	for k in 8:
		var slot := first + k
		assert_eq(field.shard_color(slot), lifted, "tint rides COLOR lifted by the named tier")
		var custom := field.shard_custom(slot)
		var v := ShatterField.shard_velocity(V, k, 8, 30.0)
		assert_almost_eq(custom.r, v.x, 0.001)
		assert_almost_eq(custom.g, v.y, 0.001)
		assert_almost_eq(field.shard_spawn_time(slot), 0.5, 0.0001, "spawn time on the consumer's clock")
		assert_almost_eq(custom.b, 0.5 - field.time_base, 0.0001, "stored relative to the time base")
		assert_eq(ShatterField.unpack_shard(custom.a), Vector2i(k, 8))
		var xf := field.shard_transform(slot)
		assert_eq(xf.origin, origin)
		assert_almost_eq(xf.get_scale().x, 24.0 * 2.0 * ShatterField.OVERSIZE, 0.0001, "one oversized quad")
		assert_almost_eq(xf.get_rotation(), 0.0, 0.0001, "never rotated — the CPU kick angle and the shader cell angle must agree")


func test_spawn_tier_is_a_named_choice() -> void:
	var field := _field()
	field.spawn_tier = Emissive.Tier.ALERT
	field.spawn_shatter(Vector2.ZERO, 10.0, TINT, Vector2.ZERO, 0.0, 1)
	assert_eq(field.shard_color(0), Emissive.at(TINT, Emissive.ALERT))
	assert_eq(Emissive.stops(Emissive.Tier.VALUE), Emissive.VALUE)
	assert_almost_eq(field.material.get_shader_parameter(&"shatter_fade_stops"), Emissive.ALERT - Emissive.INERT, 0.0001)


func test_spawn_times_are_stored_relative_to_a_time_base_for_half_float_safety() -> void:
	var field := _field()
	field.elapsed = 3600.0
	field.spawn_shatter(Vector2.ZERO, 24.0, TINT, Vector2.ZERO, 3600.0, 4)
	assert_almost_eq(field.time_base, 3600.0, 0.0001, "first spawn sets the base")
	assert_almost_eq(field.shard_custom(0).b, 0.0, 0.0001)
	assert_almost_eq(field.material.get_shader_parameter(&"shatter_elapsed"), 0.0, 0.0001, "the uniform is elapsed minus base")
	field.elapsed = 3600.1
	assert_almost_eq(field.material.get_shader_parameter(&"shatter_elapsed"), 0.1, 0.001)
	assert_eq(field.live_count(), 4)
	# Once everything has expired the next spawn re-bases: the pool is emptied
	# (they were all dead) and the new shard is again at relative 0.
	field.elapsed = 7200.0
	field.spawn_shatter(Vector2.ONE, 24.0, TINT, Vector2.ZERO, 7200.0, 4)
	assert_almost_eq(field.time_base, 7200.0, 0.0001)
	assert_eq(field.used_slots(), 4)
	assert_almost_eq(field.shard_custom(0).b, 0.0, 0.0001)
	assert_eq(field.shard_transform(0).origin, Vector2.ONE)


# -------------------------------------------------------------------- pooling


func test_two_hundred_concurrent_shatters_are_one_multimesh_and_no_children() -> void:
	var field := _field()
	for i in 200:
		field.spawn_shatter(Vector2(i * 10.0, 0.0), 24.0, TINT, Vector2.ZERO, 0.0, 8)
	assert_eq(field.get_child_count(), 0, "no node per shard, no node per shatter")
	assert_eq(field.used_slots(), 1600)
	assert_eq(field.multimesh.visible_instance_count, 1600)
	assert_eq(field.multimesh.instance_count, 2048, "capacity grows by doubling, never per shard")
	assert_eq(field.live_count(), 1600)


func test_capacity_growth_repopulates_every_earlier_slot() -> void:
	var field := _field()
	field.spawn_shatter(Vector2(1.0, 2.0), 24.0, TINT, V, 0.0, 8)
	var before := _snapshot(field)
	for i in 100:
		field.spawn_shatter(Vector2(i, i), 24.0, TINT, Vector2.ZERO, 0.0, 8)
	assert_eq(_snapshot(field).slice(0, 8), before, "growth kept the first shatter's slots byte-identical")


func test_expired_slots_are_recycled_only_when_a_spawn_needs_them() -> void:
	var field := _field()
	field.spawn_shatter(Vector2.ZERO, 24.0, TINT, Vector2.ZERO, 0.0, 8)
	field.spawn_shatter(Vector2(3.0, 3.0), 24.0, TINT, Vector2.ZERO, 0.2, 8)
	field.elapsed = 0.3
	assert_eq(field.live_count(), 8, "the first shatter expired, the second is mid-flight")
	assert_eq(field.used_slots(), 16, "expiry alone recycles nothing")
	field.spawn_shatter(Vector2(5.0, 5.0), 24.0, TINT, Vector2.ZERO, 0.3, 8)
	assert_eq(field.used_slots(), 16, "the third shatter reused the expired slots")
	assert_eq(field.multimesh.visible_instance_count, 16)
	assert_eq(field.live_count(), 16)
	assert_eq(field.shard_transform(0).origin, Vector2(5.0, 5.0), "slot 0 now belongs to the third shatter")
	assert_eq(field.shard_transform(8).origin, Vector2(3.0, 3.0), "the live shatter was untouched")


func test_scrub_is_idempotent_and_a_rewind_restores_an_expired_shard() -> void:
	var field := _field()
	field.spawn_shatter(Vector2(10.0, 10.0), 24.0, TINT, V, 0.0, 8)
	field.elapsed = 1.0
	var at_t1 := _snapshot(field)
	field.elapsed = 0.1
	assert_eq(field.live_count(), 8, "rewound below expiry: the shards are back with no spawn call")
	assert_eq(_snapshot(field), at_t1)
	field.elapsed = 1.0
	assert_eq(_snapshot(field), at_t1, "t1 -> t0 -> t1 leaves every pushed value byte-identical")
	assert_almost_eq(field.material.get_shader_parameter(&"shatter_elapsed"), 1.0, 0.0001)


func test_a_rewound_slot_is_not_handed_out_as_free() -> void:
	var field := _field()
	field.spawn_shatter(Vector2.ZERO, 24.0, TINT, Vector2.ZERO, 0.0, 4)
	field.elapsed = 5.0
	field.elapsed = 0.1
	field.spawn_shatter(Vector2.ONE, 24.0, TINT, Vector2.ZERO, 0.1, 4)
	assert_eq(field.used_slots(), 8, "live-again slots were not recycled")
	assert_eq(field.shard_transform(0).origin, Vector2.ZERO)


func test_clear_empties_the_pool() -> void:
	var field := _field()
	field.spawn_shatter(Vector2.ZERO, 24.0, TINT, Vector2.ZERO, 0.0, 8)
	field.clear()
	assert_eq(field.used_slots(), 0)
	assert_eq(field.multimesh.visible_instance_count, 0)
	assert_eq(field.spawn_shatter(Vector2.ZERO, 24.0, TINT, Vector2.ZERO, 0.0, 8), 0)


# ------------------------------------------------------------ never self-timed


func test_the_field_owns_no_clock_and_no_shared_material() -> void:
	var a := _field()
	var b := _field()
	assert_false(a.is_processing())
	assert_false(a.is_physics_processing())
	a.elapsed = 0.7
	await get_tree().process_frame
	assert_almost_eq(a.elapsed, 0.7, 0.0001, "nothing advances it but the consumer")
	assert_ne(a.material, b.material, "a shared material would scrub every field at once")
	assert_almost_eq(b.material.get_shader_parameter(&"shatter_elapsed"), 0.0, 0.0001)
	assert_almost_eq(a.material.get_shader_parameter(&"shatter_window"), WINDOW, 0.0001)
	a.flight_start = 0.6
	assert_almost_eq(a.material.get_shader_parameter(&"shatter_flight_start"), 0.6, 0.0001)
	assert_eq(a.material.resource_path, "", "the pushed-to material is the private duplicate, never the .tres")
