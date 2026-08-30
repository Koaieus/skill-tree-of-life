extends GutTest

## #677 acceptance: Reverberator's own coordinator — packets fly STRAIGHT and
## funnel INWARD to hubs (never Resonator's outward wiggle, #663 hub), climbing
## via a snap-in [LinearPath] lunge, accumulating per-node via `visit_index`
## sized/heated arrival rings, and a self-loop ghost twin that crits red on the
## return — "the teardrop itself is the tell".

const REVERBERATOR_DEF := preload("res://attack/spell/defs/reverberator.tres")
const REVERBERATOR_COORDINATOR := preload("res://ui/vfx/coordinator/spells/reverberator_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const BOLT_PACKET := preload("res://ui/vfx/projectile/visual/bolt_packet.tscn")
const GHOST_LOOP_BODY := preload("res://ui/vfx/projectile/visual/reverberator_ghost_loop_body.tscn")

const PEAK_INSTANCES: int = 40


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = REVERBERATOR_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func _entry(visit_index: int = 0, convergence_count: int = 1, crit_tier: int = 0) -> ScheduleEntry:
	var entry := ScheduleEntry.new()
	entry.beat_index = 0
	entry.beat_count = 1
	entry.visit_index = visit_index
	entry.convergence_count = convergence_count
	if crit_tier > 0:
		var hit := HitInstance.new()
		hit.crit_tier = crit_tier
		entry.hits = [hit]
	return entry


# ------------------------------------------------------------------- .tres wiring


func test_reverberator_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = REVERBERATOR_DEF
	assert_not_null(spell.vfx_coordinator_scene, "reverberator.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"reverberator.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, REVERBERATOR_COORDINATOR,
		"reverberator.tres must point at its own coordinator scene")


func test_coordinator_is_a_magic_bounce_coordinator() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord is MagicBounceCoordinator, "an inherited scene stays a MagicBounceCoordinator")


# ---------------------------------------------------------------------- paths


func test_jump_path_is_a_plain_straight_dart() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.jump_path is LinearPath, "the seed is a straight throw, never an arc")


func test_edge_path_is_a_snap_in_lunge_uphill() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.edge_path is LinearPath, "the climb is still a straight line")
	var path: LinearPath = coord.edge_path
	assert_eq(path.ease_curve, ProjectilePath.Ease.IN, "the lunge is a hard ease-IN")
	assert_gt(path.ease_strength, 0.0, "the ease must actually bite")


func test_self_loop_path_is_the_teardrop_not_the_legacy_default() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.self_loop_path is SelfLoopPath,
		"nothing may fall through to the legacy BezierArcPath default")


func test_edge_energizing_is_explicitly_not_used() -> void:
	# #677: keeping Reverberator node-centric (vs Resonator's wire-centric
	# treatment) is what keeps the two SUM-reducer siblings apart.
	var coord := _spawn_coordinator()
	for visual in [coord.jump_visual, coord.edge_visual, coord.self_loop_visual]:
		assert_not_null(visual)
		var src: String = FileAccess.get_file_as_string(visual.resource_path)
		assert_false(src.contains("EdgeEnergize") or src.contains("edge_energize"),
			"Reverberator must never reach for the edge-energize overlay")


# --------------------------------------------------------------------- visuals


func test_jump_and_edge_visuals_are_the_same_packet_arrival_composition() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.jump_visual)
	assert_eq(coord.jump_visual, coord.edge_visual,
		"JUMP and EDGE both read as a straight packet funnelling toward the hub")
	var visual: ReverberatorArrivalVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, BOLT_PACKET, "the flying body is P1-Packet, per the spec")


func test_self_loop_visual_composes_the_ghost_loop_body() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.self_loop_visual)
	var visual: ReverberatorArrivalVisual = coord.self_loop_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, GHOST_LOOP_BODY,
		"the self-loop body is the ghost-twin wrapper, not a bare packet")


# ------------------------------------------------------------------- ghost twin


func test_ghost_loop_body_spawns_a_lead_and_a_world_space_ghost() -> void:
	var body: ReverberatorGhostLoopBody = GHOST_LOOP_BODY.instantiate()
	add_child_autofree(body)
	var bolts: Array = body.find_children("*", "BoltBody", true, false)
	assert_eq(bolts.size(), 2, "one lead head plus one ghost head")
	assert_true(body._ghost.top_level, "the ghost must be world-space, like BoltBody's own trail segments")


func test_ghost_trails_the_lead_by_roughly_point_one_t() -> void:
	var body: ReverberatorGhostLoopBody = GHOST_LOOP_BODY.instantiate()
	add_child_autofree(body)
	body.global_position = Vector2(100.0, 100.0)
	body._on_launch()
	for i in 21:
		var t: float = float(i) / 20.0
		body.global_position = Vector2(100.0 + t * 400.0, 100.0)
		body._on_progress(t)
	# At t=1.0 the lead sits at x=500; the ghost, ~0.1 behind in t, should sit
	# noticeably short of it rather than coincident with the lead.
	assert_lt(body._ghost.global_position.x, 480.0,
		"the ghost must trail the lead, not sit on top of it")
	assert_gt(body._ghost.global_position.x, 100.0,
		"the ghost must have moved, not sit frozen at the origin")


func test_ghost_body_is_alpha_dimmed_not_hue_shifted() -> void:
	var body: ReverberatorGhostLoopBody = GHOST_LOOP_BODY.instantiate()
	add_child_autofree(body)
	assert_lt(body._ghost.self_modulate.a, 1.0, "the echo dims by alpha")
	assert_almost_eq(body._ghost.self_modulate.r, 1.0, 0.001, "never a hue shift (#663 D3)")


func test_crit_forwards_to_both_lead_and_ghost() -> void:
	var body: ReverberatorGhostLoopBody = GHOST_LOOP_BODY.instantiate()
	add_child_autofree(body)
	body._on_launch()
	var lead: BoltBody = body._lead
	var ghost: BoltBody = body._ghost
	var lead_calm: Color = lead.modulate
	var ghost_calm: Color = ghost.modulate
	body._on_crit(2)
	assert_ne(lead.modulate, lead_calm, "the lead retints red on a self-loop crit")
	assert_ne(ghost.modulate, ghost_calm, "the ghost retints red too — leave-and-return in red")


# --------------------------------------------------------- visit_index accumulation


func test_arrival_ring_escalates_with_visit_index() -> void:
	var coord := _spawn_coordinator()
	var first: ReverberatorArrivalVisual = coord.jump_visual.instantiate()
	add_child_autofree(first)
	first._on_launch()
	first._on_context(_entry(0))
	first._on_arrival()
	var first_ring: ImpactRing = null
	for child in first.get_children():
		if child is ImpactRing:
			first_ring = child
	assert_not_null(first_ring, "an arrival must spawn a ring")

	var fourth: ReverberatorArrivalVisual = coord.jump_visual.instantiate()
	add_child_autofree(fourth)
	fourth._on_launch()
	fourth._on_context(_entry(3))
	fourth._on_arrival()
	var fourth_ring: ImpactRing = null
	for child in fourth.get_children():
		if child is ImpactRing:
			fourth_ring = child
	assert_not_null(fourth_ring)

	assert_gt(fourth_ring.expand_radius, first_ring.expand_radius,
		"a node struck 4 times must show a visibly bigger gather than the 1st strike")
	assert_gt(fourth_ring.emissive_tier, first_ring.emissive_tier,
		"…and a hotter one — LABEL whispers, ALERT blazes")
	assert_almost_eq(first_ring.emissive_tier, Emissive.LABEL, 0.001,
		"the 1st strike whispers at LABEL")
	assert_almost_eq(fourth_ring.emissive_tier, Emissive.ALERT, 0.001,
		"the 4th strike blazes at ALERT")


func test_arrival_ring_is_in_absorb_mode() -> void:
	var coord := _spawn_coordinator()
	var visual: ReverberatorArrivalVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	visual._on_context(_entry(0))
	visual._on_arrival()
	var ring: ImpactRing = null
	for child in visual.get_children():
		if child is ImpactRing:
			ring = child
	assert_eq(ring.direction, ImpactRing.Direction.IN,
		"every landing spawns P2 in IN mode (#677 acceptance)")


func test_convergence_count_never_competes_with_the_visit_index_ramp() -> void:
	# The ring's OWN `_on_context` widens off `convergence_count` — this
	# visual must never forward context to the ring, or a converging branch
	# would re-widen a radius the visit_index ramp already set.
	var coord := _spawn_coordinator()
	var visual: ReverberatorArrivalVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	visual._on_context(_entry(0, 4))
	visual._on_arrival()
	var ring: ImpactRing = null
	for child in visual.get_children():
		if child is ImpactRing:
			ring = child
	assert_almost_eq(ring.expand_radius, visual.ring_radius_start, 0.001,
		"visit_index 0 must read at the smallest ring even with convergence_count 4")


func test_crit_tier_still_escalates_the_ring_grammar() -> void:
	var coord := _spawn_coordinator()
	var visual: ReverberatorArrivalVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	visual._on_context(_entry(0))
	visual._on_crit(2)
	visual._on_arrival()
	var ring: ImpactRing = null
	for child in visual.get_children():
		if child is ImpactRing:
			ring = child
	assert_eq(ring.crit_tier, 2, "the crit grammar still reaches the ring")
	assert_true(ring.peak_flash_fired, "tier 2+ earns the single-frame PEAK core flash")


# ------------------------------------------------------------------ batching


func test_forty_packets_share_one_texture_and_one_material() -> void:
	var materials: Array = []
	var textures: Array = []
	for _i in PEAK_INSTANCES:
		var bolt: BoltBody = BOLT_PACKET.instantiate()
		add_child_autofree(bolt)
		var head: Sprite2D = bolt.get_node("%Head")
		if not materials.has(head.material):
			materials.append(head.material)
		if not textures.has(head.texture):
			textures.append(head.texture)
	assert_eq(materials.size(), 1, "40 packets must resolve to exactly one material resource")
	assert_eq(textures.size(), 1, "…and one texture")
	assert_eq(materials[0], BoltBody.SHARED_MATERIAL)
	assert_eq(textures[0], BoltBody.HEAD_TEXTURE)


func test_ghost_loop_bodies_also_share_the_one_material() -> void:
	var materials: Array = []
	for _i in 10:
		var body: ReverberatorGhostLoopBody = GHOST_LOOP_BODY.instantiate()
		add_child_autofree(body)
		for bolt in body.find_children("*", "BoltBody", true, false):
			var head: Sprite2D = (bolt as BoltBody).get_node("%Head")
			if not materials.has(head.material):
				materials.append(head.material)
	assert_eq(materials.size(), 1, "lead and ghost heads across every self-loop share one material")
	assert_eq(materials[0], BoltBody.SHARED_MATERIAL)
