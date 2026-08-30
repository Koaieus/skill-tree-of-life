extends GutTest

## #543 D6 — the [ScheduleEntry] reaches a VISUAL.
##
## Before this, a spell visual received exactly one integer (`crit_tier`), so
## six of the eight #663 per-spell treatments had no way to know whether they
## were the first hop or the last, the big landing or a graze. Every field they
## need was data the resolver already computed and then discarded.
##
## This file pins the delivery contract itself, which is the part the art units
## build against: the coordinator stamps [member Projectile.context], and the
## projectile forwards it duck-typed as `_on_context(entry)` — before
## `_on_launch`, so a visual that sizes itself from its place in the cast does
## so on its first frame.

const _STUB := preload("res://test/unit/vfx/stub_context_visual.tscn")

var _h: SpellTestHelper


func before_each() -> void:
	_h = SpellTestHelper.new()


func _entry(index: int) -> ScheduleEntry:
	var entry := ScheduleEntry.new()
	entry.index = index
	entry.beat_index = index
	entry.beat_count = 3
	entry.magnitude = 0.5
	entry.convergence_count = 2
	entry.visit_index = 1
	entry.is_terminal = true
	entry.launch_at = 0.1
	entry.arrive_at = 0.4
	return entry


func test_a_projectile_forwards_its_entry_to_the_visual() -> void:
	var proj := Projectile.new()
	proj.visual_scene = _STUB
	proj.flight_time = 0.02
	proj.context = _entry(2)
	add_child_autofree(proj)
	proj.launch(Vector2.ZERO, Vector2(10, 0))

	var visual := proj.get_child(0) as StubContextVisual
	assert_not_null(visual, "the visual instantiates synchronously in launch()")
	assert_eq(visual.context, proj.context, "the visual got THE entry, not a copy")
	assert_eq(visual.hooks, [&"context"] as Array[StringName],
			"context arrives at instantiation, before the first frame of motion")


func test_context_precedes_launch() -> void:
	var proj := Projectile.new()
	proj.visual_scene = _STUB
	# Long flight and a real path, so the projectile is still airborne when the
	# assertion runs — an arrived projectile frees itself and takes the visual
	# whose hook log we are reading with it.
	proj.path = BezierArcPath.new()
	proj.flight_time = 5.0
	proj.context = _entry(0)
	add_child_autofree(proj)
	proj.launch(Vector2.ZERO, Vector2(10, 0))
	var visual := proj.get_child(0) as StubContextVisual
	# Frames, not `wait_seconds`: GUT's timer wait does not advance `_process`
	# on a plain Node2D here, so a seconds-based wait asserts on a projectile
	# that never moved — and reads exactly like "the hook did not fire".
	for _i in 3:
		await get_tree().process_frame
	assert_eq(visual.hooks, [&"context", &"launch"] as Array[StringName],
			"a visual must never see `_on_launch` before it knows where it is")


func test_a_visual_without_the_hook_is_simply_skipped() -> void:
	# The contract is duck-typed and every hook optional — a visual authored
	# before #543 must keep working untouched.
	var proj := Projectile.new()
	proj.visual_scene = preload("res://test/unit/vfx/stub_never_finish_visual.tscn")
	proj.context = _entry(0)
	add_child_autofree(proj)
	proj.launch(Vector2.ZERO, Vector2(10, 0))
	assert_eq(proj.get_child_count(), 1, "no error, no crash, just no forward")


## The production path, end to end: a real resolved cast, through the real
## coordinator, stamps a real entry on every bolt it spawns.
func test_the_magic_coordinator_stamps_an_entry_on_every_projectile() -> void:
	var graph := _h.make_graph([[0, 1], [1, 2]], self)
	var nodes := graph.get_skill_nodes()
	var attacker := _h.make_entity(graph, "Attacker", Color.RED)
	var defender := _h.make_entity(graph, "Defender", Color.BLUE)
	_h.give_big_hp(defender)
	_h.assign_owner(graph, attacker, [0])
	_h.assign_owner(graph, defender, [1, 2])
	var config := _h.make_config(_h.fan_all(), _h.owner_enemy(), null, {max_hops = 1})
	var tempo := PresentationTempo.new()
	tempo.beat_interval = 0.05
	tempo.beat_lead_in = 0.03
	var spell := _h.make_spell(config, [DamageEffect.new()], 10.0)
	spell.tempo = tempo
	var outcome := SpellResolver.resolve(spell, nodes[1], nodes[0], attacker, graph)

	var coord := MagicBounceCoordinator.new()
	coord.visual_scene = _STUB
	add_child_autofree(coord)
	coord.play(outcome)
	await get_tree().process_frame

	var projectiles: Array = coord.get_children().filter(func(c: Node) -> bool:
		return c is Projectile)
	assert_gt(projectiles.size(), 0, "the seed bolt spawned")
	for p in projectiles:
		var proj: Projectile = p
		assert_not_null(proj.context, "every bolt carries its schedule entry")
		assert_gte(proj.context.index, 0, "and that entry is a compiled one")
		var visual := proj.get_child(0) as StubContextVisual
		assert_eq(visual.context, proj.context, "which reached the visual")
	# Drain: `play()` was started bare, and GUT's autofree must not delete the
	# coordinator out from under a live coroutine.
	for _i in 30:
		await get_tree().process_frame
