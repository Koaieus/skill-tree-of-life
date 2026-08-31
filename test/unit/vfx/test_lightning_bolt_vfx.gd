extends GutTest

## #674 acceptance: Lightning Bolt's own coordinator — a jagged [JitterPath]
## fan (JUMP and EDGE alike) carrying a [BoltBody] jagged config that SHRINKS
## per hop (x0.5, three generations then dead), plus the standard crit ring.
## Half of the deliberate teaching pair with Leafblower (#676): same fan verb,
## opposite body-size ramp — see test_leafblower_vfx.gd for the other half.

const LIGHTNING_DEF := preload("res://attack/spell/defs/lightning_bolt.tres")
const LIGHTNING_COORDINATOR := preload("res://ui/vfx/coordinator/spells/lightning_bolt_coordinator.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const LIGHTNING_BODY := preload("res://ui/vfx/projectile/visual/lightning_bolt_body.tscn")


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = LIGHTNING_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func test_lightning_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = LIGHTNING_DEF
	assert_not_null(spell.vfx_coordinator_scene, "lightning_bolt.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"lightning_bolt.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, LIGHTNING_COORDINATOR,
		"lightning_bolt.tres must point at its own coordinator scene")


func test_coordinator_is_a_magic_bounce_coordinator() -> void:
	var coord := _spawn_coordinator()
	assert_true(coord is MagicBounceCoordinator, "an inherited scene stays a MagicBounceCoordinator")


func test_jump_and_edge_paths_are_the_jagged_jitter_path() -> void:
	var coord := _spawn_coordinator()
	for path_var in [coord.jump_path, coord.edge_path]:
		assert_true(path_var is JitterPath, "the discharge treatment is JitterPath, not a smooth arc")
		var path: JitterPath = path_var
		assert_lt(path.smoothing, 0.5, "hard corners read as crackling electricity, not a drunken swerve")
		assert_gt(path.amplitude, 0.0, "the jag must actually be visible")


func test_self_loop_path_is_filled_with_the_kit_default_not_left_null() -> void:
	# #674: "legal but rare here" — the spec still calls for it filled, not
	# silently falling through to the shared default.
	var coord := _spawn_coordinator()
	assert_not_null(coord.self_loop_path, "SELF_LOOP must not fall through to the legacy default")
	assert_true(coord.self_loop_path is SelfLoopPath, "self_loop_path must be the kit SelfLoopPath")


func test_every_per_verb_visual_slot_is_filled_with_the_same_jagged_composed_visual() -> void:
	var coord := _spawn_coordinator()
	assert_not_null(coord.jump_visual, "jump_visual must be filled")
	assert_eq(coord.jump_visual, coord.edge_visual, "JUMP and EDGE share one jagged look")
	assert_eq(coord.jump_visual, coord.self_loop_visual, "SELF_LOOP shares the same jagged look too")
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_eq(visual.body_scene, LIGHTNING_BODY, "the body is this spell's own jagged BoltBody config")
	assert_eq(visual.arrival_companions.size(), 1, "one arrival companion — the crit-grammar ring")


func test_crit_follows_the_standard_grammar_with_no_extra_authoring() -> void:
	var coord := _spawn_coordinator()
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	assert_true(visual.forward_crit_to_body,
		"Lightning does not suppress the body half of the crit grammar — a crit branch reads for free")


func test_per_hop_attenuation_shrinks_the_bolt_unmistakably() -> void:
	# #663 D3 / #674's core acceptance: a hop-3 bolt must be unmistakably
	# smaller than the seed. hop_scale is the only hop-driven ramp BoltBody
	# exposes, so this is the literal mechanism the spec's "x0.5 per hop,
	# three generations" reduces to.
	var body: BoltBody = LIGHTNING_BODY.instantiate()
	add_child_autofree(body)
	assert_almost_eq(body.hop_scale_start, 1.0, 0.001, "the seed generation reads at full size")
	assert_lt(body.hop_scale_end, 0.2, "three generations of x0.5 leaves the tail near-dead (0.125x)")


func test_per_hop_attenuation_also_dims_not_only_shrinks() -> void:
	# #686: the spec asked for the walk to read as heat fading, not just size —
	# the tier ramp is the other half of the same knob as the test above.
	var body: BoltBody = LIGHTNING_BODY.instantiate()
	add_child_autofree(body)
	assert_almost_eq(body.emissive_tier_start, Emissive.VALUE, 0.001, "the seed generation reads at full heat")
	assert_almost_eq(body.emissive_tier_end, Emissive.INERT, 0.001, "the tail generation reads near-dead")


func test_composed_visual_still_ramps_off_a_real_schedule_entry() -> void:
	var coord := _spawn_coordinator()
	var visual: ComposedProjectileVisual = coord.jump_visual.instantiate()
	add_child_autofree(visual)
	visual._on_launch()
	var entry := ScheduleEntry.new()
	entry.beat_index = 2
	entry.beat_count = 3
	visual._on_context(entry)
	assert_almost_eq(entry.beat_fraction(), 1.0, 0.001, "a sanity check on the fixture itself")
	var bolt: BoltBody = visual.get_child(0)
	assert_almost_eq(bolt._hop_fraction, 1.0, 0.001, "the last of three generations reaches the far end of the ramp")
	var ramp: float = lerpf(bolt.hop_scale_start, bolt.hop_scale_end, bolt._hop_fraction)
	assert_lt(ramp, 0.2, "the third generation's effective scale is near-dead, not merely smaller")
	var tier_ramp: float = lerpf(bolt.emissive_tier_start, bolt.emissive_tier_end, bolt._hop_fraction)
	assert_almost_eq(tier_ramp, Emissive.INERT, 0.001, "the third generation's heat is near-dead too")
