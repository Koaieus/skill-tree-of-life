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


## #663's by-eye pass raised [constant BoltBody.MAX_TRAIL_SEGMENTS] from 4 to 8,
## because a 4-segment jittered bolt reads as grain rather than an arc. The whole
## risk in that change is that `back` used to be `(i + 1) / MAX_TRAIL_SEGMENTS`,
## so raising the constant alone would have re-spread the taper and alpha ramps
## underneath all eight shipped spells without touching one authored value.
## [constant BoltBody._TAPER_SPAN] is what holds them still; these three pin it.
func test_the_scene_authors_a_segment_for_every_slot_the_cap_promises() -> void:
	var bolt := _spawn()
	var trail: Node2D = bolt.get_node(^"%Trail")
	var segments: int = 0
	for child in trail.get_children():
		if child is Sprite2D:
			segments += 1
	assert_eq(segments, BoltBody.MAX_TRAIL_SEGMENTS,
			"trail_length can be set to the cap, so the cap's worth of segments must exist to place")


func test_raising_the_cap_left_a_four_segment_trail_exactly_where_it_was() -> void:
	# The pre-#663 ramp, arithmetic: back = (i + 1) / 4, alpha = lerp(0.7, 0.05, back).
	var expected: Array[float] = [0.5375, 0.375, 0.2125, 0.05]
	var bolt := _spawn()
	bolt.trail_length = 4
	bolt._emitting = true
	bolt._apply_look()
	var trail: Node2D = bolt.get_node(^"%Trail")
	for i in expected.size():
		var seg: Sprite2D = trail.get_child(i)
		assert_almost_eq(seg.self_modulate.a, expected[i], 0.001,
				"segment %d holds the alpha it had when the cap was 4" % i)


func test_segments_past_the_taper_span_extend_the_tail_rather_than_re_spread_it() -> void:
	# The flurry: everything past the span sits at the far end of the ramp, so it
	# draws at trail_alpha_tail and is spaced apart by trail_stride in history —
	# several comparable arcs, not a longer fade.
	var bolt := _spawn()
	bolt.trail_length = BoltBody.MAX_TRAIL_SEGMENTS
	bolt.trail_alpha_tail = 0.4
	bolt._emitting = true
	bolt._apply_look()
	var trail: Node2D = bolt.get_node(^"%Trail")
	for i in range(4, BoltBody.MAX_TRAIL_SEGMENTS):
		var seg: Sprite2D = trail.get_child(i)
		assert_almost_eq(seg.self_modulate.a, 0.4, 0.001,
				"segment %d is past the span, so it carries the tail alpha" % i)
		assert_almost_eq(seg.scale.x, trail.get_child(3).scale.x, 0.001,
				"segment %d is past the span, so it is tapered no further than the fourth" % i)


## "Bigger badder spells look bigger" (#663), wired to the quantity that claim is
## actually about. `ScheduleEntry.magnitude` — this landing's share of the
## loudest landing in the same cast — has ridden `_on_context` since #543 and
## been read by nothing.
func test_magnitude_is_ignored_until_a_config_opts_in() -> void:
	var bolt := _spawn()
	bolt.head_size = 40.0
	bolt._on_context({&"magnitude": 0.25})
	assert_almost_eq(bolt.magnitude_scale(), 1.0, 0.001,
			"influence defaults to 0, so every config shipped before this takes the old path")
	assert_almost_eq(bolt._head.scale.x * 64.0, 40.0, 0.001, "the head is still its authored diameter")


func test_a_quiet_landing_draws_smaller_once_opted_in() -> void:
	var bolt := _spawn()
	bolt.head_size = 40.0
	bolt.magnitude_influence = 1.0
	bolt._on_context({&"magnitude": 0.25})
	assert_almost_eq(bolt.magnitude_scale(), 0.25, 0.001, "direct proportion at full influence")
	assert_almost_eq(bolt._head.scale.x * 64.0, 10.0, 0.001, "a quarter-magnitude landing draws a quarter as wide")


func test_magnitude_can_only_shrink_never_inflate() -> void:
	# The compiler normalizes to 0..1 with 1.0 on the biggest entry, so opting in
	# must never push a spell past its authored silhouette — including if a
	# malformed entry hands over something out of range.
	var bolt := _spawn()
	bolt.head_size = 40.0
	bolt.magnitude_influence = 1.0
	bolt._on_context({&"magnitude": 4.0})
	assert_almost_eq(bolt.magnitude_scale(), 1.0, 0.001, "clamped at the authored size")


func test_a_visual_that_never_sees_an_entry_draws_at_full_size() -> void:
	# The fallback matters more here than for the hop ramp: defaulting the other
	# way would make an opted-in body vanish whenever a coordinator hands it no
	# context.
	var bolt := _spawn()
	bolt.head_size = 40.0
	bolt.magnitude_influence = 1.0
	assert_almost_eq(bolt.magnitude_scale(), 1.0, 0.001, "no entry means 'as loud as it gets'")
	bolt._on_context(null)
	assert_almost_eq(bolt.magnitude_scale(), 1.0, 0.001, "a null entry changes nothing")
	bolt._on_context({&"beat_index": 1, &"beat_count": 3})
	assert_almost_eq(bolt.magnitude_scale(), 1.0, 0.001, "an entry without the field changes nothing")
