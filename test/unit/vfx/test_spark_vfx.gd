extends GutTest

## #671 acceptance: Spark's own coordinator, composed entirely from #670's
## kit — a straight, hard-eased [LinearPath] dart with a [BoltBody] · Small
## head and a small ("tiny P2 tick") [ImpactRing] on arrival. Single target,
## no propagation, so edge/self-loop slots are unreachable and stay unset.

const SPARK_DEF := preload("res://attack/spell/defs/spark.tres")
const SPARK_COORDINATOR := preload("res://ui/vfx/coordinator/spells/spark_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const BOLT_SMALL := preload("res://ui/vfx/projectile/visual/bolt_small.tscn")


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = SPARK_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func test_spark_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = SPARK_DEF
	assert_not_null(spell.vfx_coordinator_scene, "spark.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"spark.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, SPARK_COORDINATOR,
		"spark.tres must point at its own coordinator scene")


func test_coordinator_is_a_magic_bounce_coordinator() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord is MagicBounceCoordinator, "an inherited scene stays a MagicBounceCoordinator")


func test_jump_path_is_a_hard_eased_linear_dart() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.jump_path is LinearPath, "the seed treatment is a straight dart, not an arc")
	var path: LinearPath = coord.jump_path
	assert_eq(path.ease_curve, ProjectilePath.Ease.IN, "spec calls for a hard ease-IN")
	assert_gt(path.ease_strength, 0.0, "the ease must actually bite")


func test_jump_visual_composes_the_small_bolt_with_a_small_arrival_ring() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.jump_visual, "jump_visual must be filled")
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, BOLT_SMALL, "the body is P1-Small, per the spec")
	assert_eq(visual.arrival_companions.size(), 1, "one arrival companion — the tick ring")
	var ring: ImpactRing = visual.arrival_companions[0].instantiate()
	add_child_autofree(ring)
	var stock_ring: ImpactRing = preload("res://ui/vfx/projectile/visual/impact_ring.tscn").instantiate()
	add_child_autofree(stock_ring)
	assert_lt(ring.radius, stock_ring.radius,
		"Spark's ring reads as a 'tiny P2 tick', smaller than the kit's stock ring")


func test_edge_and_self_loop_slots_are_left_at_kit_defaults() -> void:
	# max_hops on spark.tres carries no propagation step — the spell never
	# fires an EDGE or SELF_LOOP event, so authoring those slots would be
	# dead content per the issue's own instruction.
	var coord := _spawn_coordinator()
	assert_null(coord.edge_path, "EDGE is unreachable for Spark")
	assert_null(coord.edge_visual, "EDGE is unreachable for Spark")
	assert_null(coord.self_loop_path, "SELF_LOOP is unreachable for Spark")
	assert_null(coord.self_loop_visual, "SELF_LOOP is unreachable for Spark")


func test_composed_visual_still_ramps_off_a_real_schedule_entry() -> void:
	# The per-hop/structural read the issue names: `_on_context(entry)` off a
	# real ScheduleEntry must still reach the body through Spark's own
	# composed visual (test_composed_projectile_visual.gd pins the wrapper
	# mechanism itself; this pins THIS spell's wiring of it).
	var coord := _spawn_coordinator()
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	var bolt: BoltBody = visual.get_child(0)
	visual._on_launch()
	var entry := ScheduleEntry.new()
	entry.beat_index = 0
	entry.beat_count = 1
	visual._on_context(entry)
	assert_almost_eq(bolt._hop_fraction, 0.0, 0.001, "Spark's single-wave cast sits at the near end")
