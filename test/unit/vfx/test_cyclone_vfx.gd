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


# -- #710: the closed ring, lit as a ring -----------------------------------
#
# The closing hop is the payoff of #703 and it used to light ONE node.
# `CycloneRingFlash` lays N `EdgeEnergize` overlays on the N ring edges and runs
# one front around them in the walk's own rotation over a fixed lap — one
# gesture whatever the ring's length. Two things carry it and neither is safe to
# assume: it stays on the shared material (the batch), and it is spawned exactly
# ONCE per closing event however many arcs converged there.

const RING_FLASH := preload("res://ui/vfx/projectile/visual/cyclone_ring_flash.tscn")
const _BEAT_INTERVAL: float = 0.4  ## `default_presentation_tempo.tres`


func _closing_event(ring: Array, preds: Array) -> PropagationEvent:
	var ev := _event(preds, [0.70, 0.20] if preds.size() > 1 else [0.70])
	var typed: Array[SkillNode] = []
	for n in ring:
		typed.append(n)
	ev.closed_ring = typed
	ev.target = typed[typed.size() - 1] if not typed.is_empty() else _node()
	return ev


## A ring of `n` nodes on a circle, so no two edges are degenerate.
func _ring_nodes(n: int) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(_node(Vector2(cos(a), sin(a)) * 120.0))
	return out


func _projectiles(coord: MagicBounceCoordinator) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child in coord.get_children():
		if child is Projectile:
			out.append(child)
	return out


func _ring_projectiles(coord: MagicBounceCoordinator) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for proj in _projectiles(coord):
		if proj.visual_scene == coord.ring_visual:
			out.append(proj)
	return out


func _flash(ring: Array) -> CycloneRingFlash:
	var flash: CycloneRingFlash = RING_FLASH.instantiate()
	add_child_autofree(flash)
	flash._on_context({&"closed_ring": ring})
	return flash


func _energizers(flash: CycloneRingFlash) -> Array[EdgeEnergize]:
	var out: Array[EdgeEnergize] = []
	for child in flash.get_children():
		if child is EdgeEnergize:
			out.append(child)
	return out


## The child's front, read back the only way it is observable from outside —
## the quad's x-scale, which IS the front (`test_edge_energize.gd`).
func _front_of(edge: EdgeEnergize) -> float:
	var span: float = edge.edge_origin.distance_to(edge.edge_target)
	if span <= 0.0:
		return 0.0
	var bar: Sprite2D = edge.get_node("%Bar") as Sprite2D
	return bar.scale.x * float(EdgeEnergize.BAR_TEXTURE.get_width()) / span


# ------------------------------------------------- the coordinator's ring slot


func test_cyclone_authors_a_ring_visual_and_the_shared_default_does_not() -> void:
	assert_eq(_spawn_coordinator().ring_visual, RING_FLASH,
		"Cyclone is the one spell with a ring to light")
	var shared: MagicBounceCoordinator = SHARED_DEFAULT_COORDINATOR.instantiate()
	add_child_autofree(shared)
	assert_null(shared.ring_visual,
		"null = nothing, exactly how `cancel_visual = null` behaves — the other eight are untouched")


func test_a_merged_closure_draws_two_bolts_and_exactly_one_ring() -> void:
	# The per-event dedupe, and the whole reason the ring is not an
	# `arrival_companion`: a merged landing spawns one bolt per predecessor, and
	# an ADDITIVE ring polyline drawn twice reads as a brightness bug.
	var coord := _spawn_coordinator()
	var ring := _ring_nodes(3)
	var ev := _closing_event(ring, [ring[0], ring[1]])
	var pending: Array[int] = [0]
	coord._play_projectile(ev, {}, 0.35, pending)
	assert_eq(_projectiles(coord).size(), 3, "two bolts plus one ring")
	assert_eq(_ring_projectiles(coord).size(), 1,
		"one closure is one ring however many arcs converged on it")


func test_an_open_hop_spawns_no_ring() -> void:
	var coord := _spawn_coordinator()
	var ev := _event([_node(Vector2(-50, 0))], [0.70])
	ev.target = _node(Vector2(50, 0))
	var pending: Array[int] = [0]
	coord._play_projectile(ev, {}, 0.35, pending)
	assert_eq(_ring_projectiles(coord).size(), 0, "nothing closed, nothing to light")
	assert_eq(_projectiles(coord).size(), 1, "the ordinary bolt is untouched")


func test_a_coordinator_with_no_ring_slot_spawns_none() -> void:
	var coord := _spawn_coordinator()
	coord.ring_visual = null
	var ring := _ring_nodes(4)
	var pending: Array[int] = [0]
	coord._play_projectile(_closing_event(ring, [ring[2]]), {}, 0.35, pending)
	assert_eq(_projectiles(coord).size(), 1, "an unauthored slot draws the bolt and nothing else")


func test_the_ring_rides_the_same_clock_and_the_same_drain() -> void:
	# Not `add_child` + a timer: a cast cut short must not leave rings behind, so
	# the ring is a Projectile like every other and is counted in `pending`,
	# which is what `play()` drains on.
	var coord := _spawn_coordinator()
	var ring := _ring_nodes(3)
	var pending: Array[int] = [0]
	coord._play_projectile(_closing_event(ring, [ring[1], ring[0]]), {}, 0.35, pending)
	assert_eq(pending[0], 3, "every spawned projectile, ring included, is drained on")
	var flight: Array[float] = []
	for proj in _projectiles(coord):
		flight.append(proj.flight_time)
	for f in flight:
		assert_almost_eq(f, 0.35, 0.0001,
			"the ring is spawned one lead-in early like the bolt, so it ignites ON the beat")


func test_the_ring_travels_nowhere_and_therefore_never_spins() -> void:
	# `target -> target` is the zero-length SELF_LOOP shape Projectile already
	# supports; `face_velocity`'s own length guard means it never rotates.
	var coord := _spawn_coordinator()
	var ring := _ring_nodes(5)
	var pending: Array[int] = [0]
	coord._play_projectile(_closing_event(ring, [ring[3]]), {}, 0.35, pending)
	var proj: Projectile = _ring_projectiles(coord)[0]
	assert_almost_eq(proj.rotation, 0.0, 0.0001, "a zero-length flight has no heading to face")
	assert_almost_eq(proj.global_position.distance_to(ring[4].global_position), 0.0, 0.001,
		"it sits on the landing")


# --------------------------------------------------------------- the geometry


func test_a_ring_of_n_nodes_becomes_n_overlays_laid_on_its_own_edges() -> void:
	var ring := _ring_nodes(6)
	var edges := _energizers(_flash(ring))
	assert_eq(edges.size(), 6, "N nodes, N edges — the wraparound is one of them, not a seam")
	for k in edges.size():
		var from_node: SkillNode = ring[k]
		var to_node: SkillNode = ring[(k + 1) % ring.size()]
		assert_almost_eq(edges[k].edge_origin.distance_to(from_node.global_position), 0.0, 0.001,
			"overlay %d starts at ring[%d]" % [k, k])
		assert_almost_eq(edges[k].edge_target.distance_to(to_node.global_position), 0.0, 0.001,
			"overlay %d ends at ring[%d]" % [k, (k + 1) % ring.size()])


func test_the_last_overlay_closes_the_loop_back_onto_the_first_node() -> void:
	# The edge the closer just crossed. Skipping it draws an arc, not a ring.
	var ring := _ring_nodes(4)
	var edges := _energizers(_flash(ring))
	assert_almost_eq(edges[3].edge_target.distance_to((ring[0] as SkillNode).global_position),
		0.0, 0.001, "ring[-1] -> ring[0] is the Nth edge")


func test_a_degenerate_or_absent_ring_builds_nothing() -> void:
	assert_eq(_energizers(_flash([])).size(), 0, "an empty ring is every non-closing landing")
	assert_eq(_energizers(_flash(_ring_nodes(2))).size(), 0, "two nodes are not a cycle")
	var flash: CycloneRingFlash = RING_FLASH.instantiate()
	add_child_autofree(flash)
	flash._on_context(null)
	flash._on_context(RefCounted.new())
	assert_eq(_energizers(flash).size(), 0, "an unread context shape changes nothing")


func test_sixty_overlays_of_one_ring_share_one_material() -> void:
	# The batching pin, mirroring `test_edge_energize.gd`: a ring is N overlays
	# alive at once, so a per-instance ShaderMaterial here costs 60 draws.
	var edges := _energizers(_flash(_ring_nodes(60)))
	assert_eq(edges.size(), 60)
	var materials: Array = []
	for edge in edges:
		var bar: Sprite2D = edge.get_node("%Bar") as Sprite2D
		if not materials.has(bar.material):
			materials.append(bar.material)
	assert_eq(materials.size(), 1, "a 60-edge ring must resolve to exactly one material resource")
	assert_eq(materials[0], EdgeEnergize.SHARED_MATERIAL, "and it is the one named on the class")


func test_the_composition_owns_no_shader_of_its_own() -> void:
	assert_false(FileAccess.file_exists("res://ui/vfx/projectile/visual/cyclone_ring_flash.gdshader"),
		"#710 is a COMPOSITION of kit primitives — a new shader would be a new primitive")


# -------------------------------------------------------------------- the lap


func test_the_lap_runs_the_edges_in_walk_order() -> void:
	# `clampf(p * N - k, 0, 1)`: edge 0 over the first 1/N of the lap, edge 1
	# over the next. Simultaneous ignition was rejected — it loses the "it
	# circulates" read, and Cyclone's identity is motion (#663 D3).
	assert_almost_eq(CycloneRingFlash.edge_front(0.0, 0, 4), 0.0, 0.0001, "nothing lit at p=0")
	assert_almost_eq(CycloneRingFlash.edge_front(0.25, 0, 4), 1.0, 0.0001, "edge 0 done a quarter in")
	assert_almost_eq(CycloneRingFlash.edge_front(0.25, 1, 4), 0.0, 0.0001, "edge 1 only starting")
	assert_almost_eq(CycloneRingFlash.edge_front(0.5, 1, 4), 1.0, 0.0001)
	assert_almost_eq(CycloneRingFlash.edge_front(1.0, 3, 4), 1.0, 0.0001, "the whole ring lit at p=1")


func test_the_front_is_monotonic_non_increasing_across_the_ring() -> void:
	var flash := _flash(_ring_nodes(5))
	var edges := _energizers(flash)
	flash._on_arrival()
	for p in [0.0, 0.15, 0.4, 0.72, 1.0]:
		flash._set_lap(p)
		var previous := INF
		for k in edges.size():
			var front := _front_of(edges[k])
			assert_almost_eq(front, CycloneRingFlash.edge_front(p, k, edges.size()), 0.01,
				"edge %d at p=%.2f" % [k, p])
			assert_lte(front, previous + 0.001, "the front never runs backwards along the ring")
			previous = front


func test_a_three_ring_and_a_twenty_ring_take_the_same_lap() -> void:
	# One gesture, bounded. Per-EDGE speed would give a 20-ring a ~7-beat lap
	# that stacks with the next closure.
	var small := _flash(_ring_nodes(3))
	var large := _flash(_ring_nodes(20))
	assert_almost_eq(small.lap_seconds, large.lap_seconds, 0.0001,
		"lap time is a property of the gesture, not of the ring's length")
	small._on_arrival()
	large._on_arrival()
	small._set_lap(0.5)
	large._set_lap(0.5)
	assert_almost_eq(_front_of(_energizers(small)[1]), 0.5, 0.01, "3-ring halfway: edge 1 half lit")
	assert_almost_eq(_front_of(_energizers(large)[10]), 0.0, 0.01, "20-ring halfway: edge 10 starting")
	assert_almost_eq(_front_of(_energizers(large)[9]), 1.0, 0.01, "…and edge 9 just completed")


func test_nothing_moves_before_the_beat() -> void:
	# The flight is the wind-up: the ring ignites at the same instant as the
	# closing bolt's ImpactRing, never during the lead-in.
	var flash := _flash(_ring_nodes(4))
	var edges := _energizers(flash)
	flash._on_launch()
	flash._on_progress(0.5)
	flash._on_progress(1.0)
	for edge in edges:
		assert_almost_eq(_front_of(edge), edge.initial_front, 0.005,
			"a child must sit at `initial_front` for the whole flight")


func test_each_edge_lingers_from_its_own_completion() -> void:
	# Not from the lap's: the fade is EdgeEnergize's own, armed the moment that
	# edge's front reaches 1.0.
	var flash := _flash(_ring_nodes(3))
	var edges := _energizers(flash)
	for edge in edges:
		watch_signals(edge)
		edge.linger_seconds = 0.0
	flash._on_arrival()
	flash._set_lap(0.4)
	assert_signal_emitted(edges[0], "finished", "edge 0 completes a third of the way round")
	assert_signal_not_emitted(edges[2], "finished", "edge 2 has not been reached yet")


func test_finished_waits_for_every_child() -> void:
	var flash := _flash(_ring_nodes(3))
	watch_signals(flash)
	for edge in _energizers(flash):
		edge.linger_seconds = 0.0
	flash._on_arrival()
	flash._set_lap(0.6)
	await get_tree().process_frame
	assert_signal_not_emitted(flash, "finished", "two of three edges done is not done")
	flash._set_lap(1.0)
	await get_tree().process_frame
	assert_signal_emitted(flash, "finished", "the lap ends when the last edge does")


func test_a_ringless_flash_finishes_rather_than_hanging_the_drain() -> void:
	# `pending` is what `play()` drains on, so a ring visual that never emits
	# `finished` would hold a whole cast open.
	var flash: CycloneRingFlash = RING_FLASH.instantiate()
	add_child_autofree(flash)
	watch_signals(flash)
	flash._on_context({&"closed_ring": []})
	flash._on_arrival()
	await get_tree().process_frame
	assert_signal_emitted(flash, "finished")


# ------------------------------------------------------------- tint and crit


func test_the_casters_tint_reaches_every_overlay() -> void:
	var flash := _flash(_ring_nodes(5))
	var caster_colour := Color(0.2, 0.9, 0.4)
	flash.tint = caster_colour
	for edge in _energizers(flash):
		assert_eq(edge.tint, caster_colour, "identity must reach the whole ring, not the wrapper")


func test_a_tint_stamped_before_the_ring_exists_still_lands() -> void:
	# The coordinator stamps `tint` after `launch()`, and `_on_context` runs
	# inside it — but a hand-driven order must not silently drop identity.
	var flash: CycloneRingFlash = RING_FLASH.instantiate()
	add_child_autofree(flash)
	flash.tint = Color(0.9, 0.3, 0.1)
	flash._on_context({&"closed_ring": _ring_nodes(3)})
	for edge in _energizers(flash):
		assert_eq(edge.tint, Color(0.9, 0.3, 0.1), "a stamp that beat the ring must still land")


func test_the_closure_crit_reaches_every_overlay() -> void:
	# The closing hop IS a crit (CycleCritCondition), and EdgeEnergize leans one
	# stop into one. A crit that stopped at the wrapper would be invisible.
	var calm := _energizers(_flash(_ring_nodes(3)))
	var flash := _flash(_ring_nodes(3))
	flash._on_crit(1)
	for k in 3:
		assert_gt(_energizers(flash)[k].modulate.r, calm[k].modulate.r, "overlay %d burns hotter" % k)


func test_a_crit_that_arrives_before_the_ring_is_still_applied() -> void:
	var flash: CycloneRingFlash = RING_FLASH.instantiate()
	add_child_autofree(flash)
	flash._on_crit(1)
	flash._on_context({&"closed_ring": _ring_nodes(3)})
	var calm := _energizers(_flash(_ring_nodes(3)))
	assert_gt(_energizers(flash)[0].modulate.r, calm[0].modulate.r,
		"a crit stamped before `_on_context` must not be dropped")


# ------------------------------------------------- the concurrency bound (#710)


func test_live_overlays_are_bounded_by_lap_plus_linger_over_the_beat() -> void:
	# A triangle can close EVERY beat (revisits are uncapped, b98a2ca), and each
	# closure re-runs the whole lap. So the ceiling is per-ring-edge, exactly the
	# EdgeEnergize bound with the lap folded into the linger.
	var flash: CycloneRingFlash = RING_FLASH.instantiate()
	add_child_autofree(flash)
	var edge: EdgeEnergize = flash.edge_energize_scene.instantiate()
	add_child_autofree(edge)
	var per_edge := EdgeEnergize.max_live_overlays(flash.lap_seconds + edge.linger_seconds,
		_BEAT_INTERVAL)
	assert_eq(per_edge, 9, "0.4 s lap + 2.5 s linger over 0.4 s beats is ceil(7.25)+1")
	assert_eq(3 * per_edge, 27, "a triangle re-closing every beat peaks at 27 overlays")
	assert_eq(20 * per_edge, 180, "and a 20-ring at 180 — the number to check a retune against")


func test_the_ring_reaches_the_visual_through_the_schedule_entry() -> void:
	# End to end across the seam: the coordinator hands the whole ScheduleEntry
	# over as `context` BEFORE `launch` instantiates the visual, and the visual
	# reads `entry.event.closed_ring` off it. A context wired to the bolts but
	# not to the ring would spawn an empty flash and light nothing.
	var coord := _spawn_coordinator()
	var ring := _ring_nodes(4)
	var ev := _closing_event(ring, [ring[2]])
	var entry := ScheduleEntry.new()
	entry.event = ev
	var pending: Array[int] = [0]
	coord._play_projectile(ev, {ev: entry}, 0.35, pending)
	var proj: Projectile = _ring_projectiles(coord)[0]
	var flash: CycloneRingFlash = proj.get_child(0)
	assert_eq(_energizers(flash).size(), 4, "the ring must survive the whole seam, entry included")
	assert_eq(flash.tint, coord._caster_tint, "and the caster stamp lands on it like any bolt")
