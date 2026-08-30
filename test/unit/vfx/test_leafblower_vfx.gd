extends GutTest

## #676 acceptance: Leafblower's own coordinator — a [BezierArcPath] seed, a
## fluttering [CubicBezierPath] edge, and a [BoltBody]-Streak body that GROWS
## per hop (its own leafblower_body.tscn, hop_scale 0.5 -> 4.0 — an 8x span,
## deliberately mirroring Lightning's 8x shrink so the teaching pair is symmetric),
## plus a crit-only backwash rebound on [LeafCritCondition] hits. Half of the
## deliberate teaching pair with Lightning Bolt (#674): same fan verb,
## opposite body-size ramp — see test_lightning_bolt_vfx.gd for the other half.

const LEAFBLOWER_DEF := preload("res://attack/spell/defs/leafblower.tres")
const LEAFBLOWER_COORDINATOR := preload("res://ui/vfx/coordinator/spells/leafblower_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const LEAFBLOWER_BODY := preload("res://ui/vfx/projectile/visual/leafblower_body.tscn")
const LEAFBLOWER_VISUAL := preload("res://ui/vfx/projectile/visual/leafblower_visual.tscn")


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = LEAFBLOWER_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func _stub_node(pos: Vector2) -> SkillNode:
	var node := SkillNode.new()
	node.position = pos
	autofree(node)
	return node


func test_leafblower_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = LEAFBLOWER_DEF
	assert_not_null(spell.vfx_coordinator_scene, "leafblower.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"leafblower.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, LEAFBLOWER_COORDINATOR,
		"leafblower.tres must point at its own coordinator scene")


func test_coordinator_is_a_magic_bounce_coordinator() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord is MagicBounceCoordinator, "an inherited scene stays a MagicBounceCoordinator")


func test_jump_path_is_a_bezier_arc() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.jump_path is BezierArcPath, "the seed hop is BezierArcPath, per the spec")


func test_edge_path_is_a_fluttering_cubic_bezier_not_a_heavy_sag() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.edge_path is CubicBezierPath, "travel along a real edge is a CubicBezierPath")
	var path: CubicBezierPath = coord.edge_path
	assert_ne(path.start_tangent, path.end_tangent,
		"a flutter is an S-curve — the two tangents must differ, unlike a same-direction sag")
	assert_lt(absf(path.start_strength), 0.5, "a SLIGHT lateral flutter, not Bruiser's heavy sag")


func test_self_loop_path_is_filled_with_the_kit_default_not_left_null() -> void:
	# #676: self-loops occur here and count double — the spec explicitly
	# forbids leaving this defaulted.
	var coord := _spawn_coordinator()
	assert_not_null(coord.self_loop_path, "SELF_LOOP must not fall through to the legacy default")
	assert_true(coord.self_loop_path is SelfLoopPath, "self_loop_path must be the kit SelfLoopPath")


func test_every_per_verb_visual_slot_shares_the_same_growing_streak_visual() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.jump_visual, "jump_visual must be filled")
	assert_eq(coord.jump_visual, coord.edge_visual, "JUMP and EDGE share one growing-streak look")
	assert_eq(coord.jump_visual, coord.self_loop_visual,
		"self_loop_visual must be filled too — #676 explicitly forbids leaving it defaulted")
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, LEAFBLOWER_BODY,
		"the body is Leafblower's own streak config, not the shared kit's milder bolt_streak")
	assert_eq(visual.arrival_companions.size(), 2, "the crit-grammar ring plus the leaf-crit rebound")


func test_body_growth_ramps_up_not_down() -> void:
	# The opposite ramp direction from Lightning's shrink — this is the half
	# of the teaching pair this issue owns.
	var body: BoltBody = LEAFBLOWER_BODY.instantiate()
	add_child_autofree(body)
	assert_gt(body.hop_scale_end, body.hop_scale_start, "later hops must be visibly HEAVIER, not lighter")
	# #676's headline acceptance is that the growth is as unmistakable as Lightning's
	# attenuation. Lightning spans 1.0 -> 0.125 (8x). Anything milder than a 4x span here
	# leaves the pair asymmetric and the pair stops teaching, so pin the floor.
	assert_gt(body.hop_scale_end / body.hop_scale_start, 4.0 - 0.001,
		"the growth span must be at least 4x, to mirror Lightning's shrink")


func test_composed_visual_still_ramps_off_a_real_schedule_entry() -> void:
	var coord := _spawn_coordinator()
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	var entry := ScheduleEntry.new()
	entry.beat_index = 6
	entry.beat_count = 7
	visual._on_context(entry)
	var bolt: BoltBody = visual.get_child(0)
	assert_almost_eq(bolt._hop_fraction, 1.0, 0.001, "the last hop of the chain reaches the far end of the ramp")
	var ramp: float = lerpf(bolt.hop_scale_start, bolt.hop_scale_end, bolt._hop_fraction)
	assert_gt(ramp, bolt.hop_scale_start, "hop 6 of 7 must read heavier than the seed")


func test_rebound_only_fires_on_a_crit_never_on_ordinary_arrival() -> void:
	var visual: ComposedProjectileVisual = LEAFBLOWER_VISUAL.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	var entry := ScheduleEntry.new()
	entry.origin = _stub_node(Vector2.ZERO)
	entry.target = _stub_node(Vector2(100, 0))
	visual._on_context(entry)
	visual._on_arrival()
	var rebound: LeafblowerRebound = null
	for child in visual.get_children():
		if child is LeafblowerRebound:
			rebound = child
	assert_not_null(rebound, "the rebound companion is always spawned on arrival")
	assert_false(rebound._particles.emitting, "an ordinary arrival must never fire the backwash")


func test_rebound_fires_back_along_arrival_direction_on_a_crit() -> void:
	var visual: ComposedProjectileVisual = LEAFBLOWER_VISUAL.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	var entry := ScheduleEntry.new()
	entry.origin = _stub_node(Vector2.ZERO)
	entry.target = _stub_node(Vector2(100, 0))
	visual._on_context(entry)
	visual._on_crit(2)
	visual._on_arrival()
	var rebound: LeafblowerRebound = null
	for child in visual.get_children():
		if child is LeafblowerRebound:
			rebound = child
	assert_not_null(rebound)
	assert_true(rebound._particles.emitting, "a crit arrival must fire the backwash burst")
	var expected_angle: float = Vector2(-1, 0).angle()
	assert_almost_eq(rebound._particles.global_rotation, expected_angle, 0.01,
		"origin->target was +X, so the rebound (back along arrival) must point -X")
