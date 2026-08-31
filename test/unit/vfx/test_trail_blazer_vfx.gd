extends GutTest

## #673 acceptance: Trail Blazer's own coordinator — a straight LinearPath
## fuse (`edge_path`) walked with [EdgeEnergize] (#670 P5), a small seed dart
## (`jump_path`/`jump_visual`), and a junction slam driven by
## [member ScheduleEntry.is_terminal] rather than by hop count — #663 D7
## explicitly removes the old 20-hop bound, so a hop-count guess would be
## wrong by construction.

const TRAIL_BLAZER_DEF := preload("res://attack/spell/defs/trail_blazer.tres")
const TRAIL_BLAZER_COORDINATOR := preload("res://ui/vfx/coordinator/spells/trail_blazer_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const TRAIL_BLAZER_BODY := preload("res://ui/vfx/projectile/visual/trail_blazer_body.tscn")
const TRAIL_BLAZER_EDGE_VISUAL := preload("res://ui/vfx/projectile/visual/trail_blazer_edge_visual.tscn")


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = TRAIL_BLAZER_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func _spawn_edge_visual() -> TrailBlazerEdgeVisual:
	var visual: TrailBlazerEdgeVisual = TRAIL_BLAZER_EDGE_VISUAL.instantiate()
	add_child_autofree(visual)
	return visual


# -------------------------------------------------------------------- wiring


func test_trail_blazer_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = TRAIL_BLAZER_DEF
	assert_not_null(spell.vfx_coordinator_scene, "trail_blazer.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"trail_blazer.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, TRAIL_BLAZER_COORDINATOR,
		"trail_blazer.tres must point at its own coordinator scene")


func test_coordinator_is_a_magic_bounce_coordinator() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord is MagicBounceCoordinator, "an inherited scene stays a MagicBounceCoordinator")


func test_jump_path_is_an_eased_linear_dart() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.jump_path is LinearPath, "the seed treatment is a straight dart, not an arc")
	var path: LinearPath = coord.jump_path
	assert_ne(path.ease_curve, ProjectilePath.Ease.LINEAR, "the seed hop is eased")
	assert_gt(path.ease_strength, 0.0, "the ease must actually bite")


func test_edge_path_is_a_straight_unwased_line() -> void:
	# "the wire is straight" — a constant-pace LinearPath, not the arc default.
	var coord := _spawn_coordinator()
	assert_true(coord.edge_path is LinearPath, "the wire is a straight LinearPath")
	var path: LinearPath = coord.edge_path
	assert_eq(path.ease_curve, ProjectilePath.Ease.LINEAR, "the wire travels at a constant pace")


func test_jump_visual_is_trail_blazers_own_ramping_bolt() -> void:
	# #686: the shared kit config (bolt_small.tscn) must NOT carry a per-spell
	# ramp, so Trail Blazer gets its own body config -- P1-Small's silhouette
	# plus the LABEL -> ALERT heat climb the spec calls for.
	var coord := _spawn_coordinator()
	assert_eq(coord.jump_visual, TRAIL_BLAZER_BODY,
		"the seed is Trail Blazer's own body config, not the shared bolt_small")


func test_jump_bodys_tier_climbs_from_label_towards_alert() -> void:
	var body: BoltBody = TRAIL_BLAZER_BODY.instantiate()
	add_child_autofree(body)
	assert_almost_eq(body.emissive_tier_start, Emissive.LABEL, 0.001, "the seed dart starts as a whisper")
	assert_almost_eq(body.emissive_tier_end, Emissive.ALERT, 0.001, "the far end brushes ALERT, mirroring the fuse ramp")


func test_edge_visual_is_the_trail_blazer_wrapper() -> void:
	var coord := _spawn_coordinator()
	assert_eq(coord.edge_visual, TRAIL_BLAZER_EDGE_VISUAL, "each hop ignites its edge")
	var visual: Node = coord.edge_visual.instantiate()
	add_child_autofree(visual)
	assert_true(visual is TrailBlazerEdgeVisual)


func test_self_loop_slot_is_left_at_kit_defaults() -> void:
	# TrailBlazerStep walks a degree-2 string; it never revisits a node.
	var coord := _spawn_coordinator()
	assert_null(coord.self_loop_path, "SELF_LOOP is unreachable for Trail Blazer")
	assert_null(coord.self_loop_visual, "SELF_LOOP is unreachable for Trail Blazer")


# ------------------------------------------------------------- the fuse ramp


func test_heat_ramps_from_label_towards_alert_but_never_reaches_it() -> void:
	var visual := _spawn_edge_visual()
	var near := ScheduleEntry.new()
	near.beat_index = 0
	near.beat_count = 10
	visual._on_context(near)
	var early_tier: float = visual._overlay.emissive_tier
	assert_almost_eq(early_tier, Emissive.LABEL, 0.01, "the first hop is a whisper")

	var far := ScheduleEntry.new()
	far.beat_index = 9
	far.beat_count = 10
	visual._on_context(far)
	var late_tier: float = visual._overlay.emissive_tier
	assert_gt(late_tier, early_tier, "heat ramps up across the walk")
	assert_lt(late_tier, Emissive.ALERT, "the ramp brushes ALERT without ever claiming it")


func test_context_stamps_the_edge_endpoints_from_the_schedule_entry() -> void:
	var visual := _spawn_edge_visual()
	var helper := SpellTestHelper.new()
	var graph := helper.make_graph([[0, 1]], self)
	var a: SkillNode = graph.get_skill_nodes()[0]
	a.global_position = Vector2(100.0, 40.0)
	var b: SkillNode = graph.get_skill_nodes()[1]
	b.global_position = Vector2(340.0, 260.0)

	var entry := ScheduleEntry.new()
	entry.origin = a
	entry.target = b
	entry.beat_index = 0
	entry.beat_count = 1
	visual._on_context(entry)

	assert_eq(visual._overlay.edge_origin, a.global_position)
	assert_eq(visual._overlay.edge_target, b.global_position)


# ---------------------------------------------------------------- the slam


func test_a_non_terminal_hop_never_slams() -> void:
	var visual := _spawn_edge_visual()
	var entry := ScheduleEntry.new()
	entry.is_terminal = false
	visual._on_context(entry)
	visual._on_launch()
	visual._on_arrival()

	var rings := 0
	for child in visual.get_children():
		if child is ImpactRing:
			rings += 1
	assert_eq(rings, 0, "only the junction slams — an intermediate hop is silent punctuation")


func test_the_junction_slam_is_driven_by_is_terminal_not_by_a_hop_count() -> void:
	var visual := _spawn_edge_visual()
	var entry := ScheduleEntry.new()
	entry.is_terminal = true
	entry.beat_index = 3  # an arbitrary, deliberately small hop index
	entry.beat_count = 4
	visual._on_context(entry)
	visual._on_launch()
	visual._on_arrival()

	var rings: Array[ImpactRing] = []
	for child in visual.get_children():
		if child is ImpactRing:
			rings.append(child)
	assert_eq(rings.size(), 1, "a non-crit junction slam is one spell-hue ring")
	assert_eq(rings[0].crit_tier, 2, "forced to the tier-2 shape: double ring + PEAK core")
	assert_eq(rings[0].crit_color, visual.tint, "the slam never claims a crit that did not happen")


func test_a_crit_slam_stacks_a_second_red_ring_around_the_spell_hue_core() -> void:
	var visual := _spawn_edge_visual()
	visual.tint = Color.CYAN
	var entry := ScheduleEntry.new()
	entry.is_terminal = true
	visual._on_context(entry)
	visual._on_launch()
	visual._on_crit(2)
	visual._on_arrival()

	var rings: Array[ImpactRing] = []
	for child in visual.get_children():
		if child is ImpactRing:
			rings.append(child)
	assert_eq(rings.size(), 2, "the spell-hue slam ring plus a genuine crit ring")

	var spell_hue_ring: ImpactRing = null
	var crit_ring: ImpactRing = null
	for ring in rings:
		if ring.crit_color == Color.CYAN:
			spell_hue_ring = ring
		else:
			crit_ring = ring
	assert_not_null(spell_hue_ring, "the slam ring stays pinned to the spell's own hue")
	assert_not_null(crit_ring, "a second ring carries the standard crit-red grammar")
	assert_ne(crit_ring.crit_color, Color.CYAN, "the crit ring is not laundered into the spell hue")
	assert_gt(crit_ring.expand_radius, spell_hue_ring.expand_radius,
		"the crit ring stacks AROUND the spell-hue core, not inside it")


# ----------------------------------------------------------------- the cap


func test_the_hundred_hop_cap_holds() -> void:
	# #663 D7 / #670: concurrency is bounded by EdgeEnergize's own linger, not
	# by hop count. Trail Blazer's own `max_hops` bound is being removed
	# separately, so this fires 100 sequential hops — 5x the retired bound —
	# and tracks the peak count of simultaneously-alive edge visuals.
	var beat_interval := 0.01
	var linger := 0.03
	var expected_cap: int = EdgeEnergize.max_live_overlays(linger, beat_interval)
	var alive: Array[TrailBlazerEdgeVisual] = []
	var peak := 0

	for i in 100:
		var visual: TrailBlazerEdgeVisual = TRAIL_BLAZER_EDGE_VISUAL.instantiate()
		visual.linger_seconds = linger
		add_child_autofree(visual)
		alive.append(visual)
		visual.finished.connect(func() -> void: alive.erase(visual))

		var entry := ScheduleEntry.new()
		entry.beat_index = i
		entry.beat_count = 100
		entry.is_terminal = (i == 99)
		visual._on_context(entry)
		visual._on_launch()
		visual._on_progress(1.0)
		visual._on_arrival()

		peak = maxi(peak, alive.size())
		await get_tree().create_timer(beat_interval).timeout

	# The one terminal slam ring plays out on its own (longer) duration —
	# wait for it too before asserting everything cleaned up.
	await wait_seconds(maxf(linger, 0.4) + 0.1)

	assert_true(peak <= expected_cap + 1,
		"live edge overlays must stay bounded by linger (cap %d), not by the 100-node walk (peak was %d)"
			% [expected_cap, peak])
	assert_eq(alive.size(), 0, "every overlay must eventually finish and clean up")


# --------------------------------------------------------------- discipline


func test_no_per_instance_shader_material() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://ui/vfx/projectile/visual/trail_blazer_edge_visual.gd")
	assert_false(src.contains("ShaderMaterial"),
		"per-instance variation must ride modulate/UV/transform, never a shader material")
