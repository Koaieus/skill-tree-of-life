extends GutTest

## #670 P1. The batching claim is the whole reason [BoltBody] exists, so it is
## pinned here rather than assumed: 60 simultaneous instances (Resonator's peak
## from #663's load table) must resolve to ONE texture resource and ONE
## material resource. Batching breaks on a different texture *or* a different
## material — see docs/domain/rendering-performance.md.

const BOLT_BODY := preload("res://ui/vfx/projectile/visual/bolt_body.tscn")
const CONFIGS: Array[String] = [
	"res://ui/vfx/projectile/visual/bolt_small.tscn",
	"res://ui/vfx/projectile/visual/bolt_blunt.tscn",
	"res://ui/vfx/projectile/visual/bolt_streak.tscn",
	"res://ui/vfx/projectile/visual/bolt_packet.tscn",
	"res://ui/vfx/projectile/visual/bolt_soft.tscn",
]

const PEAK_INSTANCES: int = 60


func _spawn(scene: PackedScene = BOLT_BODY) -> BoltBody:
	var bolt: BoltBody = scene.instantiate()
	add_child_autofree(bolt)
	return bolt


func _quads(bolt: BoltBody) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in bolt.find_children("*", "Sprite2D", true, false):
		out.append(child as Sprite2D)
	return out


func test_sixty_instances_share_one_texture_and_one_material() -> void:
	var textures: Array = []
	var materials: Array = []
	for _i in PEAK_INSTANCES:
		var bolt := _spawn()
		var quads := _quads(bolt)
		assert_gt(quads.size(), 0, "BoltBody must author at least the head quad")
		for quad in quads:
			if not textures.has(quad.texture):
				textures.append(quad.texture)
			if not materials.has(quad.material):
				materials.append(quad.material)
	assert_eq(textures.size(), 1, "60 bolts must resolve to exactly one texture resource")
	assert_eq(materials.size(), 1, "60 bolts must resolve to exactly one material resource")
	assert_eq(textures[0], BoltBody.HEAD_TEXTURE, "the shared texture is the one named on the class")
	assert_eq(materials[0], BoltBody.SHARED_MATERIAL, "the shared material is the one named on the class")


func test_the_five_configs_still_share_the_one_texture_and_material() -> void:
	# The configs are the vocabulary the eight per-spell units select from; if
	# any of them ever grows its own texture or material the batch is gone.
	for path in CONFIGS:
		var scene: PackedScene = load(path)
		assert_not_null(scene, "%s must load" % path)
		var bolt := _spawn(scene)
		for quad in _quads(bolt):
			assert_eq(quad.texture, BoltBody.HEAD_TEXTURE, "%s texture" % path)
			assert_eq(quad.material, BoltBody.SHARED_MATERIAL, "%s material" % path)


func test_no_instance_owns_a_shader_material() -> void:
	# #663 constraint 3, stated as a test: a per-instance ShaderMaterial is the
	# single change that turns ~60 batched quads into ~60 draw calls.
	for path in CONFIGS:
		var bolt := _spawn(load(path))
		for quad in _quads(bolt):
			assert_false(quad.material is ShaderMaterial, "%s must not own a ShaderMaterial" % path)


func test_implements_the_full_duck_contract() -> void:
	var bolt := _spawn()
	for method in ["_on_launch", "_on_progress", "_on_arrival", "_on_crit", "_on_context"]:
		assert_true(bolt.has_method(method), "BoltBody must implement %s" % method)
	assert_true(bolt.has_signal(&"finished"), "BoltBody must emit `finished`")


func test_crit_retints_the_body_to_alert() -> void:
	var bolt := _spawn()
	bolt.tint = Color.WHITE
	bolt._on_launch()
	var calm: Color = bolt.modulate
	bolt._on_crit(1)
	assert_gt(bolt.modulate.r, calm.r, "a crit body must burn hotter than a calm one")
	assert_gt(bolt.modulate.r, bolt.modulate.b, "crit retints toward damage-red")


func test_context_entry_drives_the_hop_size_ramp() -> void:
	# The #663 D3 teaching pair — Lightning shrinks, Leafblower grows — is this
	# one knob. `_on_context` takes a Variant (see the class docs), so a plain
	# duck-typed stand-in for #543's ScheduleEntry is a fair exercise of it.
	var bolt := _spawn()
	bolt.hop_scale_start = 1.0
	bolt.hop_scale_end = 2.0
	bolt._on_launch()
	var head: Sprite2D = bolt.get_node("%Head")
	var small: float = head.scale.y
	bolt._on_context({&"hop_fraction": 1.0})
	assert_gt(head.scale.y, small, "hop_fraction 1.0 must reach hop_scale_end")


func test_a_real_schedule_entry_drives_the_hop_size_ramp() -> void:
	# The dict stand-in above proves the ramp; it does NOT prove the seam with
	# #543, because a stub agrees with whatever field name this file typed.
	# #543 landed the quantity as the `beat_index` / `beat_count` PAIR, so the
	# real class is the only honest witness that the ramp is wired at all.
	var bolt := _spawn()
	bolt.hop_scale_start = 1.0
	bolt.hop_scale_end = 2.0
	bolt._on_launch()
	var head: Sprite2D = bolt.get_node("%Head")
	var near: float = head.scale.y

	var entry := ScheduleEntry.new()
	entry.beat_index = 3
	entry.beat_count = 4
	bolt._on_context(entry)
	assert_gt(head.scale.y, near, "the last beat of four must reach hop_scale_end")


func test_a_single_beat_entry_sits_at_the_near_end_of_the_ramp() -> void:
	# `beat_count` 1 is every non-magic mode and every one-wave cast. It must
	# read as "first hop", not divide by zero into the far end.
	var bolt := _spawn()
	bolt.hop_scale_start = 1.0
	bolt.hop_scale_end = 2.0
	bolt._on_launch()
	var head: Sprite2D = bolt.get_node("%Head")
	var near: float = head.scale.y

	var entry := ScheduleEntry.new()
	entry.beat_index = 0
	entry.beat_count = 1
	bolt._on_context(entry)
	assert_almost_eq(head.scale.y, near, 0.001, "a single beat must not ramp")


func test_context_entry_drives_the_hop_tier_ramp() -> void:
	# #686's core mechanism: the tier equivalent of the scale ramp above, same
	# `hop_fraction` channel. A body with start VALUE / end INERT must be
	# measurably DIMMER at the far end of the hop than at the seed.
	var bolt := _spawn()
	bolt.tint = Color.WHITE
	bolt.emissive_tier_start = Emissive.VALUE
	bolt.emissive_tier_end = Emissive.INERT
	bolt._on_launch()
	bolt._on_context({&"hop_fraction": 0.0})
	var bright: Color = bolt.modulate
	bolt._on_context({&"hop_fraction": 1.0})
	var dim: Color = bolt.modulate
	assert_lt(dim.r, bright.r, "frac=1 (INERT) must read dimmer than frac=0 (VALUE)")


func test_unset_tier_ramp_holds_emissive_tier_flat_across_the_hop() -> void:
	# The sentinel contract: a config that sets neither `emissive_tier_start`
	# nor `emissive_tier_end` (every config shipped before #686) must hold the
	# static `emissive_tier` flat across the entire hop, not silently ramp.
	var bolt := _spawn()
	bolt.tint = Color.WHITE
	bolt.emissive_tier = Emissive.LABEL
	bolt._on_launch()
	bolt._on_context({&"hop_fraction": 0.0})
	var at_zero: Color = bolt.modulate
	bolt._on_context({&"hop_fraction": 1.0})
	var at_one: Color = bolt.modulate
	assert_eq(at_zero, at_one,
		"an unset start/end sentinel must hold emissive_tier flat, never ramp")


func test_context_tolerates_null_and_unknown_shapes() -> void:
	# "Any subset, all optional" is the contract; nothing may crash on a peer
	# that hands over a shape this visual does not read.
	var bolt := _spawn()
	bolt._on_context(null)
	bolt._on_context({&"is_terminal": true})
	bolt._on_context(RefCounted.new())
	pass_test("no crash on absent / foreign context fields")


func test_arrival_finishes_the_visual() -> void:
	var bolt := _spawn()
	bolt.fade_seconds = 0.0
	bolt._on_launch()
	watch_signals(bolt)
	bolt._on_arrival()
	assert_signal_emitted(bolt, "finished")
