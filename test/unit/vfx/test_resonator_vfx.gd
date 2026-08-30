extends GutTest

## #678 acceptance: Resonator's own coordinator — waves WIGGLE on a sine and
## flood OUTWARD (never Reverberator's straight, inward-funnelling read, #663
## hub), with edge energizing as the CORE payoff ("waves live in wires") and a
## convergence gather ring that must read bigger the more branches meet.

const RESONATOR_DEF := preload("res://attack/spell/defs/resonator.tres")
const RESONATOR_COORDINATOR := preload("res://ui/vfx/coordinator/spells/resonator_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const BOLT_PACKET := preload("res://ui/vfx/projectile/visual/bolt_packet.tscn")
const GHOST_LOOP_BODY := preload("res://ui/vfx/projectile/visual/resonator_ghost_loop_body.tscn")
const EDGE_VISUAL := preload("res://ui/vfx/projectile/visual/resonator_edge_visual.tscn")

const PEAK_PACKETS: int = 60


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = RESONATOR_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func _entry(convergence_count: int = 1, crit_tier: int = 0) -> ScheduleEntry:
	var entry := ScheduleEntry.new()
	entry.beat_index = 0
	entry.beat_count = 1
	entry.convergence_count = convergence_count
	if crit_tier > 0:
		var hit := HitInstance.new()
		hit.crit_tier = crit_tier
		entry.hits = [hit]
	return entry


# ------------------------------------------------------------------- .tres wiring


func test_resonator_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = RESONATOR_DEF
	assert_not_null(spell.vfx_coordinator_scene, "resonator.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"resonator.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, RESONATOR_COORDINATOR,
		"resonator.tres must point at its own coordinator scene")


func test_coordinator_is_a_magic_bounce_coordinator() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord is MagicBounceCoordinator, "an inherited scene stays a MagicBounceCoordinator")


# ---------------------------------------------------------------------- paths


func test_jump_path_is_a_plain_straight_dart() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.jump_path is LinearPath, "the seed is a straight throw")


func test_edge_path_is_a_visible_wave_never_a_straight_line() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.edge_path is WavePath,
		"waves wiggle on the wire — never Reverberator's straight LinearPath")
	var path: WavePath = coord.edge_path
	assert_gt(path.amplitude, 0.0, "the sine must actually be visible")


func test_self_loop_path_is_the_teardrop_not_the_legacy_default() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.self_loop_path is SelfLoopPath,
		"nothing may fall through to the legacy BezierArcPath default")


# --------------------------------------------------------------------- visuals


func test_jump_visual_is_a_composed_packet_with_a_gather_ring() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.jump_visual)
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, BOLT_PACKET, "the flying body is P1-Packet, per the spec")
	assert_eq(visual.arrival_companions.size(), 1, "one arrival companion — the gather ring")


func test_edge_visual_composes_a_wave_packet_with_edge_energize_concurrently() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.edge_visual)
	var outer: ComposedProjectileVisual = coord.edge_visual.instantiate()
	add_child_autofree(outer)
	assert_eq(outer.body_scene, EDGE_VISUAL,
		"the EDGE body is the packet+energize wrapper, not a bare packet")
	var inner: ResonatorEdgeVisual = outer.get_child(0)
	var bolts: Array = inner.find_children("*", "BoltBody", true, false)
	var energizers: Array = inner.find_children("*", "EdgeEnergize", true, false)
	assert_eq(bolts.size(), 1, "the wave-riding packet body")
	assert_eq(energizers.size(), 1, "the concurrent edge-energize overlay — 'waves live in wires'")


func test_energize_overlay_is_world_space_not_dragged_by_the_bolt() -> void:
	var visual: ResonatorEdgeVisual = EDGE_VISUAL.instantiate()
	add_child_autofree(visual)
	assert_true(visual._energize.top_level,
		"the overlay must not swim/spin with a rotating, travelling Projectile parent")


func test_energize_endpoints_are_derived_from_the_schedule_entry_not_stamped_externally() -> void:
	var visual: ResonatorEdgeVisual = EDGE_VISUAL.instantiate()
	add_child_autofree(visual)
	var origin := SkillNode.new()
	origin.global_position = Vector2(10.0, 20.0)
	autofree(origin)
	var target := SkillNode.new()
	target.global_position = Vector2(310.0, 20.0)
	autofree(target)
	var entry := _entry()
	entry.origin = origin
	entry.target = target
	visual._on_context(entry)
	assert_eq(visual._energize.edge_origin, Vector2(10.0, 20.0))
	assert_eq(visual._energize.edge_target, Vector2(310.0, 20.0))


func test_self_loop_visual_composes_the_ghost_loop_body_with_a_gather_ring() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.self_loop_visual)
	var visual: ComposedProjectileVisual = coord.self_loop_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, GHOST_LOOP_BODY,
		"self-loops are explicitly weaponised here — same ghost twin Reverberator uses")


# ------------------------------------------------------------------- ghost twin


func test_ghost_loop_body_spawns_a_lead_and_a_world_space_ghost() -> void:
	var body: ResonatorGhostLoopBody = GHOST_LOOP_BODY.instantiate()
	add_child_autofree(body)
	var bolts: Array = body.find_children("*", "BoltBody", true, false)
	assert_eq(bolts.size(), 2, "one lead head plus one ghost head")
	assert_true(body._ghost.top_level, "the ghost must be world-space")


func test_ghost_trails_the_lead_by_roughly_point_one_t() -> void:
	var body: ResonatorGhostLoopBody = GHOST_LOOP_BODY.instantiate()
	add_child_autofree(body)
	body.global_position = Vector2(100.0, 100.0)
	body._on_launch()
	for i in 21:
		var t: float = float(i) / 20.0
		body.global_position = Vector2(100.0 + t * 400.0, 100.0)
		body._on_progress(t)
	assert_lt(body._ghost.global_position.x, 480.0, "the ghost must trail the lead")
	assert_gt(body._ghost.global_position.x, 100.0, "the ghost must have moved")


# --------------------------------------------------------- convergence gather


func test_gather_ring_reads_bigger_for_a_four_way_than_a_two_way_convergence() -> void:
	var two_way: ComposedProjectileVisual = preload(
		"res://ui/vfx/projectile/visual/resonator_jump_visual.tscn").instantiate()
	add_child_autofree(two_way)
	two_way._on_launch()
	two_way._on_context(_entry(2))
	two_way._on_arrival()
	var two_ring: ImpactRing = null
	for child in two_way.get_children():
		if child is ImpactRing:
			two_ring = child

	var four_way: ComposedProjectileVisual = preload(
		"res://ui/vfx/projectile/visual/resonator_jump_visual.tscn").instantiate()
	add_child_autofree(four_way)
	four_way._on_launch()
	four_way._on_context(_entry(4))
	four_way._on_arrival()
	var four_ring: ImpactRing = null
	for child in four_way.get_children():
		if child is ImpactRing:
			four_ring = child

	assert_not_null(two_ring)
	assert_not_null(four_ring)
	assert_gt(four_ring.expand_radius, two_ring.expand_radius,
		"a 4-way convergence must read bigger than a 2-way")
	assert_eq(four_ring.direction, ImpactRing.Direction.IN, "arrival on a convergence gathers (IN)")


func test_convergence_crit_still_reaches_the_gather_ring() -> void:
	var visual: ComposedProjectileVisual = preload(
		"res://ui/vfx/projectile/visual/resonator_jump_visual.tscn").instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	visual._on_context(_entry(2))
	visual._on_crit(2)
	visual._on_arrival()
	var ring: ImpactRing = null
	for child in visual.get_children():
		if child is ImpactRing:
			ring = child
	assert_eq(ring.crit_tier, 2, "the crit grammar reaches the gather ring")
	assert_true(ring.peak_flash_fired, "tier 2 is the loudest visual in the game")


# ---------------------------------------------------------- batching (~60 peak)


func test_sixty_packets_share_one_texture_and_one_material() -> void:
	var materials: Array = []
	var textures: Array = []
	for _i in PEAK_PACKETS:
		var bolt: BoltBody = BOLT_PACKET.instantiate()
		add_child_autofree(bolt)
		var head: Sprite2D = bolt.get_node("%Head")
		if not materials.has(head.material):
			materials.append(head.material)
		if not textures.has(head.texture):
			textures.append(head.texture)
	assert_eq(materials.size(), 1, "60 packets must resolve to exactly one material resource")
	assert_eq(textures.size(), 1, "…and one texture")
	assert_eq(materials[0], BoltBody.SHARED_MATERIAL)
	assert_eq(textures[0], BoltBody.HEAD_TEXTURE)


func test_sixty_edge_overlays_share_a_second_distinct_material_two_batches_not_120_draws() -> void:
	var packet_materials: Array = []
	var overlay_materials: Array = []
	for _i in PEAK_PACKETS:
		var visual: ResonatorEdgeVisual = EDGE_VISUAL.instantiate()
		add_child_autofree(visual)
		var bolt: BoltBody = visual._body
		var head: Sprite2D = bolt.get_node("%Head")
		if not packet_materials.has(head.material):
			packet_materials.append(head.material)
		var overlay: EdgeEnergize = visual._energize
		var bar: Sprite2D = overlay.get_node("%Bar")
		if not overlay_materials.has(bar.material):
			overlay_materials.append(bar.material)
	assert_eq(packet_materials.size(), 1, "60 wave packets share one material")
	assert_eq(overlay_materials.size(), 1, "60 edge overlays share ANOTHER one material")
	assert_ne(packet_materials[0], overlay_materials[0],
		"two distinct shared materials — two batches, not one mixed one")
	assert_eq(packet_materials[0], BoltBody.SHARED_MATERIAL)
	assert_eq(overlay_materials[0], EdgeEnergize.SHARED_MATERIAL)
