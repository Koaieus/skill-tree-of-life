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


func test_the_body_is_a_streak_config_that_opts_into_arc_weighting() -> void:
	# #709 left the shared bolt_streak in place, a pure composition fix. #708
	# then needed a config of its own to turn weighting on — the kit default is
	# OFF precisely so the eight non-splitting spells stay untouched.
	var visual := _spawn_visual()
	var body: BoltBody = visual.body_scene.instantiate()
	add_child_autofree(body)
	assert_almost_eq(body.arc_weight_influence, 1.0, 0.001,
		"Cyclone draws its arcs in direct proportion to the share they carry")
	assert_gt(body.head_size, 14.0,
		"a bigger base head, so a 0.20 offshoot is still visible once scaled down")


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


# -- #708: drawing the curl ------------------------------------------------

const _CYCLONE_DEF_708 := preload("res://attack/spell/defs/cyclone.tres")


func _event(preds: Array, shares: Array, turn: float = 1.0) -> PropagationEvent:
	var ev := PropagationEvent.new()
	var typed: Array[SkillNode] = []
	for p in preds:
		typed.append(p)
	ev.predecessors = typed
	ev.incident_shares = PackedFloat32Array(shares)
	ev.turn_sign = turn
	ev.origin = typed[0] if not typed.is_empty() else null
	return ev


func _node(pos: Vector2 = Vector2.ZERO) -> SkillNode:
	var n := SkillNode.new()
	n.position = pos
	autofree(n)
	return n


func test_arc_weight_reaches_the_body_through_the_wrapper() -> void:
	# The same failure mode as the caster tint before #671: the wrapper sits
	# BETWEEN the projectile and the body, so a stamp that stops at the wrapper
	# is invisible in exactly the composed case every spell uses.
	var visual := _spawn_visual()
	visual.arc_weight = 0.2
	var body: BoltBody = visual.get_child(0)
	assert_almost_eq(body.arc_weight, 0.2, 0.001, "the share must reach the body")


func test_arc_weight_stamped_before_the_body_exists_is_re_pushed() -> void:
	# The stamp can legitimately land before `_ready` instantiates the body —
	# which is why `tint` carries a setter AND a re-push, and why this one must.
	var visual: ComposedProjectileVisual = CYCLONE_VISUAL.instantiate()
	visual.arc_weight = 0.35
	add_child_autofree(visual)
	var body: BoltBody = visual.get_child(0)
	assert_almost_eq(body.arc_weight, 0.35, 0.001,
		"a stamp that beat instantiation must still land on the body")


func test_arc_weight_does_not_dim_the_impact_ring() -> void:
	# Rank deliberately does NOT ride the wrapper's `modulate`: it is a Node2D,
	# so modulate cascades, and a rank-3 offshoot would dim the very crit ring
	# #709 exists to make visible.
	var visual := _spawn_visual()
	visual.arc_weight = 0.2
	visual._on_launch()
	visual._on_crit(1)
	visual._on_arrival()
	assert_eq(visual.modulate, Color.WHITE, "the wrapper must not carry the weight as modulate")
	assert_eq(_ring_of(visual).modulate, Color.WHITE, "punctuation lands at full strength")


func test_a_spine_draws_more_than_twice_the_weakest_offshoot() -> void:
	# The #704 complaint, as pixels: 0.70 and 0.20 must not be the same picture.
	var body: BoltBody = _spawn_visual().body_scene.instantiate()
	add_child_autofree(body)
	body.arc_weight = 0.70
	var spine := body.arc_scale()
	body.arc_weight = 0.20
	var offshoot := body.arc_scale()
	assert_gt(spine, offshoot * 2.0,
		"the spine must read more than twice the offshoot (%.2f vs %.2f)" % [spine, offshoot])


func test_a_spell_that_never_splits_is_untouched_by_the_new_channel() -> void:
	# The kit default is influence 0, so the other eight spells provably take
	# the pre-#708 path whatever weight is stamped on them.
	var body: BoltBody = preload("res://ui/vfx/projectile/visual/bolt_streak.tscn").instantiate()
	add_child_autofree(body)
	assert_almost_eq(body.arc_weight_influence, 0.0, 0.001, "weighting is opt-in")
	body.arc_weight = 0.2
	assert_almost_eq(body.arc_scale(), 1.0, 0.001, "an opted-out body ignores the stamp entirely")


# -- pairing: the one place alignment can silently lie ---------------------


func test_each_bolt_of_a_merge_is_paired_with_its_own_arc_s_share() -> void:
	var coord := _spawn_coordinator()
	var a := _node(Vector2(-50, 0))
	var b := _node(Vector2(50, 0))
	var ev := _event([a, b], [0.70, 0.20])
	var indices := coord._arc_indices_for(ev)
	assert_eq(indices.size(), 2, "a two-arc merge draws two bolts")
	assert_almost_eq(coord._share_at(ev, indices[0]), 0.70, 0.001)
	assert_almost_eq(coord._share_at(ev, indices[1]), 0.20, 0.001)


func test_a_merge_that_filters_down_to_one_arc_refuses_to_guess() -> void:
	# A merged event whose predecessors filter to one non-null entry still
	# carries several shares, and index 0 need not be the survivor's. Reading it
	# anyway would pair a bolt with ANOTHER arc's weight — worse than not
	# weighting it, because it is wrong rather than merely absent.
	var coord := _spawn_coordinator()
	var ev := _event([_node(), null], [0.70, 0.20])
	var indices := coord._arc_indices_for(ev)
	assert_eq(indices.size(), 1, "one drawable arc falls back to the single origin")
	assert_almost_eq(coord._share_at(ev, indices[0]), 1.0, 0.001,
		"an unpairable bolt draws undivided rather than borrowing a neighbour's weight")


func test_an_ordinary_single_arc_landing_still_carries_its_own_share() -> void:
	var coord := _spawn_coordinator()
	var ev := _event([_node()], [0.40])
	var indices := coord._arc_indices_for(ev)
	assert_eq(indices.size(), 1)
	assert_almost_eq(coord._share_at(ev, indices[0]), 0.40, 0.001,
		"the overwhelmingly common case must be weighted, not defaulted")


# -- handedness ------------------------------------------------------------


func test_a_clockwise_cast_leaves_the_authored_path_untouched() -> void:
	var coord := _spawn_coordinator()
	coord._turn_sign = 1.0
	var authored: ProjectilePath = coord.edge_path
	assert_same(coord._handed_path(PropagationEvent.Verb.EDGE, authored), authored,
		"the authored amplitude already expresses the +1 look; nothing should allocate")


func test_a_counter_clockwise_cast_flips_the_bow() -> void:
	var coord := _spawn_coordinator()
	coord._turn_sign = -1.0
	var authored: WavePath = coord.edge_path
	var flipped: WavePath = coord._handed_path(PropagationEvent.Verb.EDGE, authored)
	assert_lt(flipped.handedness, 0.0, "flipping CycloneStep.clockwise must flip the picture")
	assert_almost_eq(flipped.amplitude, authored.amplitude, 0.001,
		"the width knob is untouched — handedness is its own field, not a sign on amplitude")


func test_flipping_never_mutates_the_shared_path_resource() -> void:
	# ProjectilePath resources are shared and live. Writing the sign onto one
	# would flip it for every projectile of every spell that references it.
	var coord := _spawn_coordinator()
	var authored: WavePath = coord.edge_path
	coord._turn_sign = -1.0
	coord._handed_path(PropagationEvent.Verb.EDGE, authored)
	assert_almost_eq(authored.handedness, 1.0, 0.001, "the shared resource keeps its authored sign")


func test_the_flipped_path_is_built_once_per_cast_never_once_per_bolt() -> void:
	# Handedness is constant for a whole cast, so a 60-bolt hex wheel must cost
	# ONE duplicate. A per-bolt duplicate is the silent regression here.
	var coord := _spawn_coordinator()
	coord._turn_sign = -1.0
	var first: ProjectilePath = coord._handed_path(PropagationEvent.Verb.EDGE, coord.edge_path)
	for _i in 60:
		assert_same(coord._handed_path(PropagationEvent.Verb.EDGE, coord.edge_path), first,
			"every bolt of the cast shares one flipped path")


func test_the_cast_s_handedness_is_read_off_the_timeline() -> void:
	var coord := _spawn_coordinator()
	var outcome := AttackOutcome.new()
	# The seed reports 0 — a JUMP is not a turn — so the resolve must look past
	# it rather than concluding the whole cast is unhanded.
	outcome.timeline.append(_event([_node()], [1.0], 0.0))
	outcome.timeline.append(_event([_node()], [0.70], -1.0))
	assert_almost_eq(coord._resolve_turn_sign(outcome), -1.0, 0.001,
		"the seed's 0 must not mask the cast's real handedness")


func test_a_rotation_blind_spell_reports_no_handedness() -> void:
	var coord := _spawn_coordinator()
	var outcome := AttackOutcome.new()
	outcome.timeline.append(_event([_node()], [1.0], 0.0))
	assert_almost_eq(coord._resolve_turn_sign(outcome), 0.0, 0.001)
	assert_same(coord._handed_path(PropagationEvent.Verb.EDGE, coord.edge_path), coord.edge_path,
		"a spell with no handedness never allocates a flipped path")


func test_a_flipped_path_mirrors_the_bow_across_the_segment() -> void:
	# The behavioural half: the two paths must land on opposite sides of the
	# straight line, and both must still hit the endpoints exactly.
	var straight := WavePath.new()
	straight.amplitude = 26.0
	straight.frequency = 0.5
	straight.decay = 0.0
	var mirrored: WavePath = straight.duplicate()
	mirrored.handedness = -1.0
	var origin := Vector2.ZERO
	var target := Vector2(100, 0)
	var a := straight.evaluate(0.5, origin, target)
	var b := mirrored.evaluate(0.5, origin, target)
	assert_almost_eq(a.y, -b.y, 0.001, "the bow mirrors across the segment")
	assert_ne(a.y, 0.0, "and it actually bows")
	assert_almost_eq(mirrored.evaluate(0.0, origin, target).distance_to(origin), 0.0, 0.001,
		"a flipped path still starts exactly at the origin")
	assert_almost_eq(mirrored.evaluate(1.0, origin, target).distance_to(target), 0.0, 0.001,
		"and still lands exactly on the target")
