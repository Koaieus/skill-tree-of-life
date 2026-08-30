extends GutTest

## #672 acceptance: Bruiser's own coordinator — a sagging [CubicBezierPath]
## (blunt mass under its own weight, not a lobbed arc) carrying a
## [BoltBody] · Blunt head, an [ImpactRing] thud and a one-shot [DustPuff],
## with the body pinned dim even on a crit — "a spell that cannot kill must
## not have a body that goes full neon."

const BRUISER_DEF := preload("res://attack/spell/defs/bruiser.tres")
const BRUISER_COORDINATOR := preload("res://ui/vfx/coordinator/spells/bruiser_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const BOLT_BLUNT := preload("res://ui/vfx/projectile/visual/bolt_blunt.tscn")


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = BRUISER_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func test_bruiser_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = BRUISER_DEF
	assert_not_null(spell.vfx_coordinator_scene, "bruiser.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"bruiser.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, BRUISER_COORDINATOR,
		"bruiser.tres must point at its own coordinator scene")


func test_jump_and_edge_paths_sag_rather_than_lob() -> void:
	var coord := _spawn_coordinator()
	for path_var in [coord.jump_path, coord.edge_path]:
		assert_true(path_var is CubicBezierPath, "blunt mass is a CubicBezierPath, not the default arc")
		var path: CubicBezierPath = path_var
		# "Sagging" = both tangents point the SAME way (dips below the
		# straight line) — the opposite of the lobbed-mortar shape, which the
		# class docs name as both tangents at (0, -1).
		assert_almost_eq(path.start_tangent.y, path.end_tangent.y, 0.001,
			"both tangents must point the same way to sag rather than arc")
		assert_gt(path.start_tangent.y, 0.0, "a positive Y tangent dips DOWN in Godot's screen space")


func test_jump_and_edge_visuals_are_the_same_composed_blunt_body() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.jump_visual)
	assert_eq(coord.jump_visual, coord.edge_visual, "Bruiser never self-loops; jump and edge share one look")
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, BOLT_BLUNT, "the body is P1-Blunt, per the spec")
	assert_eq(visual.arrival_companions.size(), 2, "the thud ring plus the one-shot dust puff")


func test_self_loop_slot_is_left_at_kit_defaults() -> void:
	# TakeTopNStep walks distinct neighbours; a self-loop cannot occur.
	var coord := _spawn_coordinator()
	assert_null(coord.self_loop_path, "SELF_LOOP is unreachable for Bruiser")
	assert_null(coord.self_loop_visual, "SELF_LOOP is unreachable for Bruiser")


func test_body_never_forwards_crit_even_though_the_ring_still_escalates() -> void:
	# #672 acceptance: "the body stays at VALUE on crit — only the ring
	# escalates. A crit Bruiser must still not read as lethal."
	var coord := _spawn_coordinator()
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_false(visual.forward_crit_to_body, "Bruiser must suppress the body half of the crit grammar")
	var bolt: BoltBody = visual.get_child(0)
	visual._on_launch()
	var calm: Color = bolt.modulate
	visual._on_crit(2)
	assert_eq(bolt.modulate, calm, "the body must not swell or retint on a Bruiser crit")

	visual._on_arrival()
	var ring: ImpactRing = null
	for child in visual.get_children():
		if child is ImpactRing:
			ring = child
	assert_not_null(ring, "the ring companion must still be spawned on arrival")
	assert_eq(ring.crit_tier, 2, "the ring alone carries the escalation")


func test_composed_visual_still_reads_a_real_schedule_entry() -> void:
	# The per-hop/structural read the issue names, wired through Bruiser's
	# own composition (test_composed_projectile_visual.gd pins the wrapper
	# mechanism itself).
	var coord := _spawn_coordinator()
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	var entry := ScheduleEntry.new()
	entry.beat_index = 2
	entry.beat_count = 3
	entry.is_terminal = false
	visual._on_context(entry)
	assert_almost_eq(entry.beat_fraction(), 1.0, 0.001, "a sanity check on the fixture itself")
	var bolt: BoltBody = visual.get_child(0)
	assert_almost_eq(bolt._hop_fraction, 1.0, 0.001, "the last hop of three reaches the far end of the ramp")
