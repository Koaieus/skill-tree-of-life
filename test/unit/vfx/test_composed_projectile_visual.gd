extends GutTest

## [ComposedProjectileVisual] (#671/#672): the wrapper that lets a per-spell
## visual pair a flying [BoltBody] config with arrival-only companions
## ([ImpactRing]'s crit grammar, Bruiser's dust puff) — a [Projectile]'s
## `visual_scene` slot only takes ONE scene per verb, so this is what makes
## "body + ring" composable at all.

const COMPOSED := preload("res://ui/vfx/projectile/visual/composed_projectile_visual.gd")
const STUB_CONTEXT_VISUAL := preload("res://test/unit/vfx/stub_context_visual.tscn")
const BOLT_SMALL := preload("res://ui/vfx/projectile/visual/bolt_small.tscn")
const IMPACT_RING := preload("res://ui/vfx/projectile/visual/impact_ring.tscn")


func _spawn(body: PackedScene = null, companions: Array[PackedScene] = [],
		forward_crit: bool = true) -> ComposedProjectileVisual:
	var wrapper := ComposedProjectileVisual.new()
	wrapper.body_scene = body
	wrapper.arrival_companions = companions
	wrapper.forward_crit_to_body = forward_crit
	add_child_autofree(wrapper)
	return wrapper


func test_implements_the_full_duck_contract() -> void:
	var wrapper := _spawn(BOLT_SMALL)
	for method in ["_on_launch", "_on_progress", "_on_arrival", "_on_crit", "_on_context"]:
		assert_true(wrapper.has_method(method), "ComposedProjectileVisual must implement %s" % method)
	assert_true(wrapper.has_signal(&"finished"), "ComposedProjectileVisual must emit `finished`")


func test_body_is_instantiated_once_up_front() -> void:
	var wrapper := _spawn(BOLT_SMALL)
	var bolts := wrapper.find_children("*", "BoltBody", true, false)
	assert_eq(bolts.size(), 1, "the body is a single always-present child")


func test_launch_progress_and_context_forward_to_the_body_only() -> void:
	# The body must see the whole flight; a companion (ring, dust) must not
	# exist yet — it is spawned only at arrival (see the next test).
	var wrapper := _spawn(STUB_CONTEXT_VISUAL)
	var entry := ScheduleEntry.new()
	entry.beat_index = 1
	entry.beat_count = 2
	wrapper._on_context(entry)
	wrapper._on_launch()
	wrapper._on_progress(0.5)
	var stub: StubContextVisual = wrapper.get_child(0)
	assert_eq(stub.context, entry, "the body receives the context entry")
	assert_eq(stub.hooks, [&"context", &"launch"] as Array[StringName],
		"context arrives before launch, exactly as Projectile forwards it")


func test_arrival_companions_are_spawned_only_at_arrival() -> void:
	var wrapper := _spawn(BOLT_SMALL, [IMPACT_RING])
	assert_eq(wrapper.find_children("*", "ImpactRing", true, false).size(), 0,
		"a companion must not exist before arrival — ImpactRing's autoplay-on-ready "
		+ "guard only recognises a DIRECT Projectile parent, so spawning it early "
		+ "would fire it a full flight ahead of impact")
	wrapper._on_arrival()
	assert_eq(wrapper.find_children("*", "ImpactRing", true, false).size(), 1,
		"arrival spawns exactly the configured companion")


func test_a_real_schedule_entry_reaches_the_body_hop_ramp_through_the_wrapper() -> void:
	# Proves the per-hop/structural read (#543 D6's ScheduleEntry) is wired
	# THROUGH this composition, not just on the primitive in isolation
	# (test_bolt_body.gd already pins that half).
	var wrapper := _spawn(BOLT_SMALL)
	var bolt: BoltBody = wrapper.get_child(0)
	bolt.hop_scale_start = 1.0
	bolt.hop_scale_end = 2.0
	wrapper._on_launch()
	var head: Sprite2D = bolt.get_node("%Head")
	var near: float = head.scale.y

	var entry := ScheduleEntry.new()
	entry.beat_index = 3
	entry.beat_count = 4
	wrapper._on_context(entry)
	assert_gt(head.scale.y, near, "the hop ramp must move through the wrapper's forwarded context")


func test_crit_reaches_the_ring_regardless_of_the_body_flag() -> void:
	# Bruiser (#672) needs the ring to escalate on crit while the body stays
	# dim — this is what makes that split possible without touching BoltBody.
	var wrapper := _spawn(BOLT_SMALL, [IMPACT_RING], false)
	wrapper._on_launch()
	var bolt: BoltBody = wrapper.get_child(0)
	var calm: Color = bolt.modulate
	wrapper._on_crit(2)
	assert_eq(bolt.modulate, calm, "forward_crit_to_body = false keeps the body's look untouched")
	wrapper._on_arrival()
	var ring: ImpactRing = wrapper.find_children("*", "ImpactRing", true, false)[0]
	assert_eq(ring.crit_tier, 2, "the companion still receives the crit tier")


func test_crit_reaches_the_body_when_the_flag_is_left_at_its_default() -> void:
	var wrapper := _spawn(BOLT_SMALL)
	wrapper._on_launch()
	var bolt: BoltBody = wrapper.get_child(0)
	var calm: Color = bolt.modulate
	wrapper._on_crit(2)
	assert_gt(bolt.modulate.r, calm.r, "forward_crit_to_body defaults true — Spark's body still swells on crit")


func test_finished_waits_for_every_signalling_child_and_never_races_the_await() -> void:
	# The regression this guards: emitting `finished` synchronously inside
	# `_on_arrival()` would fire before `Projectile`'s `await visual.finished`
	# has registered, hanging the await forever. Deferred emission is the fix.
	var wrapper := _spawn(BOLT_SMALL, [IMPACT_RING])
	var bolt: BoltBody = wrapper.get_child(0)
	bolt.fade_seconds = 0.0
	var seen := [false]
	wrapper.finished.connect(func() -> void: seen[0] = true)
	wrapper._on_launch()
	wrapper._on_arrival()
	# Not yet — even the zero-fade body's `finished` is deferred one frame.
	assert_false(seen[0], "finished must not fire synchronously inside _on_arrival")
	await wait_seconds(0.5)
	assert_true(seen[0], "finished must eventually fire once every child has drained")


func test_a_companion_with_no_finished_signal_does_not_block_completion() -> void:
	# A companion that doesn't declare `finished` at all is, per the visual
	# contract, already done the instant it's spawned — it must not gate the
	# wrapper's own completion.
	var scene_root := Node2D.new()
	var bare := PackedScene.new()
	bare.pack(scene_root)
	scene_root.free()
	var wrapper := _spawn(BOLT_SMALL, [bare])
	var bolt: BoltBody = wrapper.get_child(0)
	bolt.fade_seconds = 0.0
	var seen := [false]
	wrapper.finished.connect(func() -> void: seen[0] = true)
	wrapper._on_launch()
	wrapper._on_arrival()
	await wait_seconds(0.5)
	assert_true(seen[0], "a signal-less companion must not gate the wrapper's own finished")
