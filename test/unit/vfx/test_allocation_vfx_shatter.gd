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


# --- #871: crack seams glow first, the DISC shatters, no rim rays ------------
# Timing contract only (CPU reference curves mirroring the shader); the look
# itself is judged under a renderer. Authored numbers are the owner's to tune,
# so nothing below pins a literal stop count or window.


func test_crack_glow_ramps_up_to_flight_start_then_is_gone() -> void:
	var p0 := 0.6
	assert_almost_eq(AllocationVFX.crack_glow_at(0.0, p0), 0.0, 0.0001)
	var prev := 0.0
	for i in range(1, 10):
		var g := AllocationVFX.crack_glow_at(p0 * float(i) / 10.0, p0)
		assert_true(g >= prev, "crack glow must not dip before the disc lets go")
		prev = g
	assert_true(prev > 0.5, "crack glow should be nearly peaked just before flight_start")
	# The crack phase ENDS at flight_start — from here on only shards draw.
	assert_almost_eq(AllocationVFX.crack_glow_at(p0, p0), 0.0, 0.0001)
	assert_almost_eq(AllocationVFX.crack_glow_at(0.9, p0), 0.0, 0.0001)


func test_crack_rays_fire_late_in_the_crescendo_and_are_gone_at_release() -> void:
	# #871 reopened: "the earth's crust cracks, the cracks light up, UNTIL
	# light beams fire out of them" — beams are a late phase of the same
	# crescendo, never before `onset`, never after the disc lets go.
	var p0 := 0.6
	var onset := 0.6
	assert_almost_eq(AllocationVFX.ray_glow_at(0.0, p0, onset), 0.0, 0.0001)
	assert_almost_eq(AllocationVFX.ray_glow_at(p0 * onset * 0.5, p0, onset), 0.0, 0.0001,
			"no beams while the cracks are still only lighting up")
	assert_almost_eq(AllocationVFX.ray_glow_at(p0 * onset, p0, onset), 0.0, 0.0001,
			"beams start from zero at onset")
	var prev := 0.0
	for i in range(1, 10):
		var prog := lerpf(p0 * onset, p0, float(i) / 10.0)
		var g := AllocationVFX.ray_glow_at(prog, p0, onset)
		assert_true(g >= prev, "beams only grow toward the burst")
		prev = g
	assert_true(prev > 0.5, "beams should be nearly peaked just before flight_start")
	# Never draw a ray during shard flight — that is the old "still glowing
	# after the burst" complaint from another angle.
	assert_almost_eq(AllocationVFX.ray_glow_at(p0, p0, onset), 0.0, 0.0001)
	assert_almost_eq(AllocationVFX.ray_glow_at(0.9, p0, onset), 0.0, 0.0001)
	# The crack glow is the beams' floor: a beam never leads its own crack.
	for i in range(0, 101):
		var prog := p0 * float(i) / 100.0
		assert_true(AllocationVFX.ray_glow_at(prog, p0, onset)
				<= AllocationVFX.crack_glow_at(prog, p0) + 0.0001,
				"ray ramp must trail the crack glow")


func test_shard_bloom_peaks_at_release_and_fizzles_to_zero() -> void:
	var p0 := 0.6
	assert_almost_eq(AllocationVFX.shard_bloom_at(0.0, p0), 0.0, 0.0001)
	assert_almost_eq(AllocationVFX.shard_bloom_at(p0 * 0.5, p0), 0.0, 0.0001)
	assert_almost_eq(AllocationVFX.shard_bloom_at(p0, p0), 1.0, 0.0001)
	var mid := AllocationVFX.shard_bloom_at(lerpf(p0, 1.0, 0.5), p0)
	assert_true(mid > 0.0 and mid < 1.0, "bloom decays across the flight")
	assert_almost_eq(AllocationVFX.shard_bloom_at(1.0, p0), 0.0, 0.0001)


func test_shard_bloom_is_a_named_tier_pushed_onto_the_material() -> void:
	_vfx.shatter_shard_bloom_tier = Emissive.Tier.PEAK
	var mat := _vfx.get_shard_field().material as ShaderMaterial
	var pushed: Variant = mat.get_shader_parameter(&"shard_bloom_stops")
	assert_not_null(pushed, "shard_bloom_stops uniform is not on the material")
	assert_almost_eq(float(pushed), Emissive.stops(Emissive.Tier.PEAK), 0.0001)
	_vfx.shatter_shard_bloom_tier = Emissive.Tier.INERT
	assert_almost_eq(float(mat.get_shader_parameter(&"shard_bloom_stops")), 0.0, 0.0001)


func test_crack_beams_are_a_named_tier_and_onset_pushed_onto_the_material() -> void:
	# #871 reopened: #257's rim-anchored rays were the "rim glows and bursts"
	# read and went; what came back are beams anchored to the CRACKS, gated
	# by `ray_glow_at` (see the timing test above) so nothing draws past the
	# rim once the disc has let go. Their peak is a tier, never a hand float.
	_vfx.shatter_ray_tier = Emissive.Tier.ALERT
	_vfx.shatter_ray_onset = 0.7
	var mat := _vfx.get_shard_field().material as ShaderMaterial
	var pushed: Variant = mat.get_shader_parameter(&"ray_stops")
	assert_not_null(pushed, "ray_stops uniform is not on the material")
	assert_almost_eq(float(pushed), Emissive.stops(Emissive.Tier.ALERT), 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter(&"ray_onset")), 0.7, 0.0001)
	_vfx.shatter_ray_tier = Emissive.Tier.INERT
	assert_almost_eq(float(mat.get_shader_parameter(&"ray_stops")), 0.0, 0.0001)


# ---------------------------------------------- a dying node keeps its glyph (#843)

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _carved_node() -> SkillNode:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(node)
	node.archetype = load("res://archetypes/strength.tres")
	return node


func _assert_cascade_carries_carve(node: SkillNode, expected: CarveParams) -> void:
	assert_eq(expected.carve_kind, 1, "the fixture is a carved (POLYGON) node")
	var owner := Entity.new()
	autofree(owner)
	var field := _vfx.get_shard_field()
	_vfx._on_cascade_started([[node]], owner)
	var before := field.used_slots()
	_vfx._on_force_deallocated(node, owner)
	assert_eq(field.used_slots() - before, _vfx.shatter_shard_count)
	for slot in range(before, field.used_slots()):
		assert_true(field.shard_carve(slot).equals(expected),
				"slot %d carries %s, got %s" % [slot, expected, field.shard_carve(slot)])


func test_a_cascade_shatter_carries_the_dying_nodes_carve() -> void:
	var node := _carved_node()
	_assert_cascade_carries_carve(node, node.carve_params())


func test_a_fogged_node_still_shatters_with_its_carve() -> void:
	var node := _carved_node()
	var expected := node.carve_params()
	node.visible = false
	_assert_cascade_carries_carve(node, expected)


func test_the_shard_material_binds_the_shared_carve_samplers() -> void:
	var mat := _vfx.get_shard_field().material as ShaderMaterial
	assert_not_null(mat.get_shader_parameter(&"gem_lut"), "GEM carves need the shared LUT")
	if CarveAtlas.shared() != null:
		assert_not_null(mat.get_shader_parameter(&"carve_atlas"), "TEXTURE carves need the shared atlas")
