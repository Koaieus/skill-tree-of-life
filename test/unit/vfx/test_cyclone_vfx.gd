extends GutTest

## #709 acceptance: Cyclone's coordinator used to point both verb slots at a
## BARE [code]bolt_streak.tscn[/code] — no [ComposedProjectileVisual], therefore
## no [ImpactRing], therefore no crit grammar at all. Since [ImpactRing] is the
## sole home of that grammar (#663 D6), every [CycleCritCondition] crit the
## spell rolled rendered as literally nothing: #703 measured 31 of them on a
## single hex wheel and a player saw none.
##
## Loop closure is the one crit that survived the #703 redesign ("sparkle and a
## damage floor"), so this is the spell's payoff moment. These tests pin that it
## is drawn, and that it is drawn by CONFIGURING the shared ring rather than by
## authoring a second effect.

const CYCLONE_DEF := preload("res://attack/spell/defs/cyclone.tres")
const CYCLONE_COORDINATOR := preload("res://ui/vfx/coordinator/spells/cyclone_coordinator.tscn")
const CYCLONE_VISUAL := preload("res://ui/vfx/projectile/visual/cyclone_visual.tscn")
const SHARED_DEFAULT_COORDINATOR := preload("res://ui/vfx/coordinator/magic_bounce_coordinator.tscn")
const BOLT_STREAK := preload("res://ui/vfx/projectile/visual/bolt_streak.tscn")


func _spawn_coordinator() -> MagicBounceCoordinator:
	var coord: MagicBounceCoordinator = CYCLONE_COORDINATOR.instantiate()
	add_child_autofree(coord)
	return coord


func _spawn_visual() -> ComposedProjectileVisual:
	var visual: ComposedProjectileVisual = CYCLONE_VISUAL.instantiate()
	add_child_autofree(visual)
	return visual


func _ring_of(visual: ComposedProjectileVisual) -> ImpactRing:
	for child in visual.get_children():
		if child is ImpactRing:
			return child
	return null


func test_cyclone_def_points_at_its_own_coordinator_not_the_shared_default() -> void:
	var spell: SpellDef = CYCLONE_DEF
	assert_not_null(spell.vfx_coordinator_scene, "cyclone.tres must set a coordinator")
	assert_ne(spell.vfx_coordinator_scene, SHARED_DEFAULT_COORDINATOR,
		"cyclone.tres must not point at the shared MagicBounceCoordinator default")
	assert_eq(spell.vfx_coordinator_scene, CYCLONE_COORDINATOR,
		"cyclone.tres must point at its own coordinator scene")


func test_both_verb_slots_are_composed_not_a_bare_body() -> void:
	# The #709 headline. Before this issue both slots held BOLT_STREAK directly,
	# which is a BoltBody and owns no crit grammar whatsoever.
	var coord := _spawn_coordinator()
	assert_ne(coord.jump_visual, BOLT_STREAK, "the seed must not be a bare BoltBody any more")
	assert_ne(coord.edge_visual, BOLT_STREAK, "an edge hop must not be a bare BoltBody any more")
	assert_eq(coord.jump_visual, coord.edge_visual, "seed and edge share one curl look")
	assert_true(_spawn_visual() is ComposedProjectileVisual,
		"the visual must be the shared ComposedProjectileVisual wrapper, not a bespoke scene")


func test_the_body_is_still_the_streak_the_spell_already_had() -> void:
	# #709 is a composition fix, not a re-look: the flying body is unchanged,
	# the ring is what was missing.
	var visual := _spawn_visual()
	assert_eq(visual.body_scene, BOLT_STREAK, "the streak body carries over untouched")


func test_arrival_spawns_the_shared_impact_ring() -> void:
	var visual := _spawn_visual()
	visual._on_launch()
	visual._on_arrival()
	assert_not_null(_ring_of(visual), "arrival must spawn the kit's ImpactRing companion")


func test_a_non_crit_landing_rings_at_tier_zero() -> void:
	# ImpactRing is the IMPACT punctuation first and the crit grammar second —
	# it plays on every arrival, and the grammar "overrides this upward; it
	# never overrides it downward". So the crit must read as an ESCALATION of
	# the ring, never as the ring's mere existence.
	var visual := _spawn_visual()
	visual._on_launch()
	visual._on_arrival()
	var ring := _ring_of(visual)
	assert_not_null(ring, "an ordinary hop still gets its impact ring")
	assert_eq(ring.crit_tier, 0, "an ordinary hop must not be dressed as a crit")


func test_a_loop_closure_escalates_the_same_ring() -> void:
	var visual := _spawn_visual()
	visual._on_launch()
	visual._on_crit(1)
	visual._on_arrival()
	var ring := _ring_of(visual)
	assert_not_null(ring, "the crit must reach a ring at all — this is what #709 fixes")
	assert_eq(ring.crit_tier, 1, "the closure's tier must reach the ring that draws the grammar")


func test_tier_two_escalates_within_one_scene_never_a_second_effect() -> void:
	var visual := _spawn_visual()
	visual._on_launch()
	visual._on_crit(2)
	visual._on_arrival()
	var rings: int = 0
	for child in visual.get_children():
		if child is ImpactRing:
			rings += 1
	assert_eq(rings, 1, "tier 2 escalates INSIDE ImpactRing — a second scene would break #663 D6")
	assert_eq(_ring_of(visual).crit_tier, 2, "the tier must arrive so the double ring + PEAK flash can arm")


func test_the_ring_expands_outward_it_does_not_gather() -> void:
	# Resonator's crit is convergence and absorbs (IN). Cyclone's is a loop
	# CLOSING and then feeding forward through closing_gain — #704's word for
	# what it must read as is "an epicentre", and an epicentre radiates.
	var visual := _spawn_visual()
	visual._on_launch()
	visual._on_arrival()
	assert_eq(_ring_of(visual).direction, ImpactRing.Direction.OUT,
		"the closure radiates; it is not a gather")


func test_the_ring_does_not_autoplay_before_arrival() -> void:
	# ImpactRing autoplays on _ready unless its DIRECT parent is a Projectile,
	# so a ring authored as a static child one level down would fire a whole
	# flight early. The wrapper spawns it at arrival precisely to sidestep that.
	var visual := _spawn_visual()
	visual._on_launch()
	visual._on_progress(0.5)
	assert_null(_ring_of(visual), "no ring may exist mid-flight — only at arrival")


func test_caster_tint_reaches_the_body_and_never_the_ring() -> void:
	# The wrapper sits BETWEEN the projectile and the body, so a stamp that
	# stops at the wrapper is invisible in exactly the composed case. The ring
	# is punctuation owning its own tier colour: tinting it with the caster's
	# would make "where it fired" read as identity rather than as placement.
	var visual := _spawn_visual()
	var caster_colour := Color(0.2, 0.9, 0.4)
	visual.tint = caster_colour
	visual._on_launch()
	visual._on_arrival()
	var body: BoltBody = visual.get_child(0)
	assert_eq(body.tint, caster_colour, "the caster's colour must reach the flying body")
	assert_ne(_ring_of(visual).tint, caster_colour, "the ring keeps its own grammar colour")


func test_a_crit_reaches_the_body_too_the_storm_escalates() -> void:
	# Unlike Bruiser (#672), which must never read as lethal, Cyclone's body
	# SHOULD swell on a closure — the storm finding its loop is the payoff.
	var visual := _spawn_visual()
	assert_true(visual.forward_crit_to_body, "the storm escalates on a loop closure, body included")


func test_self_loop_slot_is_deliberately_unfilled() -> void:
	# Unlike Leafblower (#676), which was explicitly forbidden from leaving this
	# defaulted, Cyclone CANNOT emit a SELF_LOOP: Curl drops self-loops before
	# the angular sort, because a zero-length direction has no angular slot.
	# Authoring a look for a verb the spell cannot produce would be dead weight.
	var coord := _spawn_coordinator()
	assert_null(coord.self_loop_visual, "Cyclone emits no SELF_LOOP; the slot stays empty on purpose")
