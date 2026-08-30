extends GutTest

## #675 acceptance: Healing Beam's own coordinator — soft P1 orbs drifting on
## a low-amplitude [WavePath], absorbed by a P2 ring in `IN` mode rather than
## exploding. The whole point is that this spell's `PropagationConfig` carries
## no filter at all, so it heals hostile nodes too (#663's table) — the art
## must be honest about that, which means the orb never branches on
## ownership and never reads the caster's identity colour. Crit is the one
## documented exception to "never gold" (#663 D5 / owner call 2026-08-30,
## recorded in `.claude/rules/ui-palette.md`).

const HEALING_BEAM_DEF := preload("res://attack/spell/defs/healing_beam.tres")
const HEALING_BEAM_COORDINATOR := preload("res://ui/vfx/coordinator/spells/healing_beam_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const HEALING_BEAM_ORB := preload("res://ui/vfx/projectile/visual/healing_beam_orb_visual.tscn")
const HEALING_BEAM_ABSORB_RING := preload("res://ui/vfx/projectile/visual/healing_beam_absorb_ring.tscn")
const HEALING_BEAM_CANCEL_RING := preload("res://ui/vfx/projectile/visual/healing_beam_cancel_ring.tscn")

## The XP/gold value pinned in `.claude/rules/ui-palette.md` — the ONLY hue
## a crit heal may claim, per the documented carve-out.
const XP_GOLD := Color(0.8909, 0.7204, 0.2596, 1)


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = HEALING_BEAM_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func _spawn_orb() -> HealingBeamOrbVisual:
	var orb: HealingBeamOrbVisual = HEALING_BEAM_ORB.instantiate()
	add_child_autofree(orb)
	return orb


# -------------------------------------------------------------------- wiring


func test_healing_beam_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = HEALING_BEAM_DEF
	assert_not_null(spell.vfx_coordinator_scene, "healing_beam.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"healing_beam.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, HEALING_BEAM_COORDINATOR,
		"healing_beam.tres must point at its own coordinator scene")


func test_coordinator_is_a_magic_bounce_coordinator() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord is MagicBounceCoordinator, "an inherited scene stays a MagicBounceCoordinator")


func test_jump_path_is_a_low_apex_bezier_arc() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.jump_path is BezierArcPath, "the seed treatment is a low arc")
	var path: BezierArcPath = coord.jump_path
	var stock := BezierArcPath.new()
	assert_lt(path.apex_height, stock.apex_height * 0.5,
		"the apex must read as LOW against the kit's own default")


func test_edge_path_is_a_low_amplitude_wave() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord.edge_path is WavePath, "travel is a lazy sinuous drift, not a straight dart")
	var path: WavePath = coord.edge_path
	var stock := WavePath.new()
	assert_lt(path.amplitude, stock.amplitude,
		"the drift must read as LOW against the kit's own default")


func test_self_loop_path_does_not_fall_through_to_a_legacy_default() -> void:
	# The null propagation filter means self-loops genuinely fire for this
	# spell (unlike Spark/Bruiser/Trail Blazer, where the slot stays null) —
	# so leaving this unset would silently hand a self-loop event a
	# `BezierArcPath.new()` with its full-size default apex.
	var coord := _spawn_coordinator()
	assert_not_null(coord.self_loop_path, "self-loops fire for Healing Beam; the slot must be filled")
	assert_true(coord.self_loop_path is SelfLoopPath,
		"a same-node bounce wants the dedicated teardrop shape, not a degenerate arc")


func test_every_reachable_visual_slot_points_at_the_healing_beam_orb() -> void:
	var coord := _spawn_coordinator()
	assert_eq(coord.jump_visual, HEALING_BEAM_ORB, "jump_visual must be filled")
	assert_eq(coord.edge_visual, HEALING_BEAM_ORB, "edge_visual must be filled")
	assert_eq(coord.self_loop_visual, HEALING_BEAM_ORB,
		"self_loop_visual must be the same orb — the null filter means self-loops DO fire")
	assert_not_null(coord.cancel_visual, "cancel_visual must be filled")
	assert_ne(coord.cancel_visual, preload("res://ui/vfx/projectile/visual/cancel_dissipate.tscn"),
		"a heal fizzling should sigh via a tiny absorb ring, not pop via the generic cancel dissipate")


# ---------------------------------------------------------------- the orb


func test_orb_body_is_soft_with_no_trail() -> void:
	var orb := _spawn_orb()
	var body: BoltBody = orb.get_child(0)
	assert_true(body is BoltBody, "the flight body is P1-Soft")
	assert_eq(body.trail_length, 0, "alpha-led and blurred, no trail — an attack streaks, a heal doesn't")


func test_orb_body_is_pinned_neutral_regardless_of_caster() -> void:
	var orb := _spawn_orb()
	var body: BoltBody = orb.get_child(0)
	var neutral := Emissive.NEUTRAL
	assert_almost_eq(body.tint.r, neutral.r, 0.001)
	assert_almost_eq(body.tint.g, neutral.g, 0.001)
	assert_almost_eq(body.tint.b, neutral.b, 0.001)
	assert_ne(body.tint, Color.WHITE, "must be the named NEUTRAL off-white, not a bare white default")


func test_orb_exposes_no_tint_property_so_the_caster_stamp_is_a_no_op() -> void:
	# MagicBounceCoordinator stamps `if "tint" in v: v.set("tint", caster_color)`
	# on every projectile's visual root right after launch (#663 D4). The whole
	# point of this spell's honesty is that the stamp must find nothing to grab.
	var orb := _spawn_orb()
	assert_false("tint" in orb, "the orb root must not expose a tint property")


func test_arrival_spawns_the_absorb_ring_in_contracting_mode() -> void:
	var orb := _spawn_orb()
	orb._on_launch()
	orb._on_arrival()
	var ring: ImpactRing = null
	for child in orb.get_children():
		if child is ImpactRing:
			ring = child
	assert_not_null(ring, "the absorb ring must be spawned on arrival")
	assert_eq(ring.direction, ImpactRing.Direction.IN,
		"absorbed, not exploded — the ring must contract onto the node")


func test_absorb_ring_configured_scene_matches_the_composed_arrival_companion() -> void:
	var visual: HealingBeamOrbVisual = HEALING_BEAM_ORB.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.arrival_companions.size(), 1, "one arrival companion — the absorb ring")
	assert_eq(visual.arrival_companions[0], HEALING_BEAM_ABSORB_RING)


# --------------------------------------------------------------- crit gold


func test_non_crit_arrival_never_reads_gold() -> void:
	var orb := _spawn_orb()
	orb._on_launch()
	orb._on_arrival()
	var ring: ImpactRing = null
	for child in orb.get_children():
		if child is ImpactRing:
			ring = child
	assert_not_null(ring)
	assert_eq(ring.crit_tier, 0, "no crit landed")
	assert_ne(ring.tint, XP_GOLD, "a non-crit heal must not read gold")


func test_crit_heal_reads_gold_via_the_absorb_rings_crit_color() -> void:
	var ring: ImpactRing = HEALING_BEAM_ABSORB_RING.instantiate()
	add_child_autofree(ring)
	assert_eq(ring.crit_color, XP_GOLD,
		"the documented #663 D5 carve-out: a critical heal claims the XP/gold hue, not crit-red")


func test_crit_tier_1_escalates_through_the_normal_single_ring_grammar() -> void:
	var orb := _spawn_orb()
	orb._on_launch()
	orb._on_crit(1)
	orb._on_arrival()
	var ring: ImpactRing = null
	for child in orb.get_children():
		if child is ImpactRing:
			ring = child
	assert_not_null(ring)
	assert_eq(ring.crit_tier, 1)
	assert_eq(ring.active_ring_count(), 1, "tier 1 is a single ring")
	assert_false(ring.has_peak_flash(), "tier 1 does not earn the PEAK core")
	assert_eq(ring.crit_color, XP_GOLD, "tier 1 still reads gold, not crit-red")


func test_crit_tier_2_gets_double_ring_and_peak_core_still_in_gold() -> void:
	var orb := _spawn_orb()
	orb._on_launch()
	orb._on_crit(2)
	orb._on_arrival()
	var ring: ImpactRing = null
	for child in orb.get_children():
		if child is ImpactRing:
			ring = child
	assert_not_null(ring)
	assert_eq(ring.active_ring_count(), 2, "tier 2+ is a double ring")
	assert_true(ring.has_peak_flash(), "tier 2+ earns the single-frame PEAK core")
	assert_eq(ring.crit_color, XP_GOLD, "the escalation stays gold, never crit-red")


func test_orb_body_itself_never_escalates_to_crit_red() -> void:
	# The body reads identical friend/foe right up to the moment it lands —
	# only the arrival ring may carry the crit grammar, and in gold, not red.
	var orb := _spawn_orb()
	var body: BoltBody = orb.get_child(0)
	orb._on_launch()
	var calm: Color = body.modulate
	orb._on_crit(2)
	assert_eq(body.modulate, calm, "the flying orb must not retint or swell on a crit")


# ---------------------------------------------------------------- the sigh


func test_cancel_visual_is_a_tinier_absorb_ring_than_the_arrival_ring() -> void:
	var cancel: ImpactRing = HEALING_BEAM_CANCEL_RING.instantiate()
	add_child_autofree(cancel)
	var arrival: ImpactRing = HEALING_BEAM_ABSORB_RING.instantiate()
	add_child_autofree(arrival)
	assert_eq(cancel.direction, ImpactRing.Direction.IN, "a fizzle sighs inward too, never pops outward")
	assert_lt(cancel.expand_radius, arrival.expand_radius,
		"cancel_visual must read as a TINY absorb, not the full arrival ring")
	assert_lt(cancel.duration, arrival.duration, "a fizzle is quicker than a landed heal")


# ------------------------------------------------------------- the honesty


func test_no_ownership_branch_anywhere_in_the_spells_own_files() -> void:
	# The enemy-healing trap must be honest: an orb flying into a hostile node
	# looks IDENTICAL to one flying into a friendly node. That is only true if
	# nothing in this spell's own diff ever asks a relation question at all.
	var paths := [
		"res://ui/vfx/projectile/visual/healing_beam_orb_visual.gd",
	]
	for path in paths:
		var src: String = FileAccess.get_file_as_string(path)
		assert_false(src.contains("owned_by"), "%s must not branch on owned_by" % path)
		assert_false(src.contains("ownership_bit"), "%s must not branch on ownership_bit" % path)
		assert_false(src.contains("OwnershipBit"), "%s must not branch on OwnershipBit" % path)


func test_no_per_instance_shader_material() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://ui/vfx/projectile/visual/healing_beam_orb_visual.gd")
	assert_false(src.contains("ShaderMaterial"),
		"per-instance variation must ride modulate/UV/transform, never a shader material")
