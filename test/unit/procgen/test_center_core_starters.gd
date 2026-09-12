extends GutTest

## Pins #758's camp-relative spacing floor for [CenterCoreStarters]. Owner's
## acceptance spec, settled in a `/swarmify` pass 2026-09-10 (issue comment):
## cross-camp separation is a FLOOR (`viability_radius * min_dist`, every
## attempt, never degrading) and same-camp separation is HALF that
## (`0.5 * viability_radius * min_dist`), still degrading toward `min_dist` on
## [method StarterPlacement.degrade_spacing]'s existing curve. Before this
## fix, `plan()` discarded camp identity entirely and applied one degrading
## ask to every pair regardless of camp — a dice roll on whether an enemy
## opens on top of the player.
##
## Property tests on hand-built inputs, per the spec — never on an authored
## preset (the owner tunes `viability_radius` per preset and that must not
## turn these red), except acceptance 5, which is explicitly about the
## shipped `first_level.tres` preset surviving the floor at max roster size.


## Matches [GraphProcgenConfig]'s defaults (`node_radius = 32`,
## `node_padding = 14`), same constant [test_camp_annulus_starters.gd] uses.
const _MIN_DIST := 78.0


# ── Acceptance 1 — the cross-camp floor holds, swept across seeds ─────────
#
## Red today: today's code discards camp identity, so a random-fill anchor
## can land inside another camp's floor whenever the seed is unlucky.
func test_cross_camp_floor_holds_across_seeds() -> void:
	var placement := CenterCoreStarters.new()
	placement.viability_radius = 2.0
	var camp_sizes: Array[int] = [1, 4]
	var mask := CircularShapeMask.new()
	mask.radius = 170.0
	var required := placement.viability_radius * _MIN_DIST

	for seed_val in range(1, 21):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		var pts := placement.plan(camp_sizes, 170.0, _MIN_DIST, rng, mask, 200)
		assert_eq(pts.size(), 5, "seed %d: expected all 5 contenders placed" % seed_val)
		if pts.size() != 5:
			continue
		# camp 0 = index 0 (the centred contender), camp 1 = indices 1..4 —
		# every pair here is cross-camp.
		for i in range(1, pts.size()):
			var d: float = pts[0].position.distance_to(pts[i].position)
			assert_true(d >= required - 0.5,
				"seed %d: cross-camp pair (0,%d) at %.2f < floor %.2f" % [seed_val, i, d, required])


# ── Acceptance 2 — same-camp spacing may be closer; the rule is asymmetric ─
#
## Red today: today's uniform degrading ask never demands the FULL cross-camp
## floor from a cross-camp pair either, so the cross-camp assertion below
## fails just as it does in acceptance 1 — the point of this test is that it
## fails for an asymmetric reason once fixed: cross pairs hold the floor,
## same-camp pairs are allowed under it.
func test_same_camp_spacing_permitted_closer_than_cross_camp_floor() -> void:
	var placement := CenterCoreStarters.new()
	placement.viability_radius = 3.0
	var camp_sizes: Array[int] = [1, 6]
	var mask := CircularShapeMask.new()
	mask.radius = 300.0
	var cross_required := placement.viability_radius * _MIN_DIST

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts := placement.plan(camp_sizes, 300.0, _MIN_DIST, rng, mask, 200)
	assert_eq(pts.size(), 7, "premise: all 7 contenders placed")
	if pts.size() != 7:
		return

	# Cross-camp: index 0 (camp 0) against every camp-1 member (indices 1..6).
	for i in range(1, pts.size()):
		var d: float = pts[0].position.distance_to(pts[i].position)
		assert_true(d >= cross_required - 0.5,
			"cross-camp pair (0,%d) at %.2f < floor %.2f" % [i, d, cross_required])

	# Same-camp: at least one pair within camp 1 sits under the cross-camp
	# floor — the mask is tight enough that packing 6 members at the full
	# ask is infeasible, so the degrading same-camp curve must have kicked in.
	var closest_same_camp := INF
	for i in range(1, pts.size()):
		for j in range(i + 1, pts.size()):
			closest_same_camp = minf(closest_same_camp,
				pts[i].position.distance_to(pts[j].position))
	assert_true(closest_same_camp < cross_required,
		"expected at least one same-camp pair under the cross-camp floor, closest was %.2f"
		% closest_same_camp)


## Guards [method StarterPlacement.required_spacing] directly: at a low
## `viability_radius` (1.5 is authored today, e.g. `coop_versus/starting_points.tres`),
## an un-guarded `0.5 * viability_radius * min_dist` full ask (0.75 * min_dist)
## sits BELOW `min_dist` — so the degrade curve would start under its own
## floor and an early attempt could place two same-camp starters overlapping.
## `required_spacing` clamps the same-camp full ask up to `min_dist`.
func test_same_camp_spacing_never_starts_below_min_dist() -> void:
	var placement := StarterPlacement.new()
	placement.viability_radius = 1.5
	assert_eq(placement.required_spacing(_MIN_DIST, 0, 200, true), _MIN_DIST,
		"a low viability_radius must not let the same-camp curve start under min_dist")


# ── Acceptance 3 — determinism ─────────────────────────────────────────────
func test_deterministic_across_identically_seeded_rng() -> void:
	var placement := CenterCoreStarters.new()
	placement.viability_radius = 2.0
	var camp_sizes: Array[int] = [2, 3]
	var mask := CircularShapeMask.new()
	mask.radius = 1500.0

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 77
	var pts_a := placement.plan(camp_sizes, 1500.0, _MIN_DIST, rng_a, mask, 200)

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 77
	var pts_b := placement.plan(camp_sizes, 1500.0, _MIN_DIST, rng_b, mask, 200)

	assert_eq(pts_a.size(), pts_b.size())
	for i in pts_a.size():
		assert_eq(pts_a[i].position, pts_b[i].position,
			"index %d diverged between two identically-seeded runs" % i)
		assert_eq(pts_a[i].id, pts_b[i].id)


# ── Acceptance 4 — a crowded map is loud, not silent ───────────────────────
#
## Red today: a mask small enough that the cross-camp floor is geometrically
## unsatisfiable for ANY camp-1 member (max distance from the mask's own
## centre is less than the floor) still lets today's code place several of
## them, because the ask degrades uniformly toward `min_dist` regardless of
## camp. Once cross-camp spacing is a non-degrading floor, none of them can
## ever be placed here — and the existing `push_warning` path (extended, not
## removed) must still fire rather than the caller silently getting fewer
## starters than it asked for.
func test_crowded_map_warns_when_cross_camp_floor_is_unsatisfiable() -> void:
	var placement := CenterCoreStarters.new()
	placement.viability_radius = 3.0
	var camp_sizes: Array[int] = [1, 3]
	var mask := CircularShapeMask.new()
	mask.radius = 150.0
	var required := placement.viability_radius * _MIN_DIST
	assert_true(mask.radius < required,
		"premise: no point in the mask can be `required` away from the origin")

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pts := placement.plan(camp_sizes, 150.0, _MIN_DIST, rng, mask, 200)

	assert_eq(pts.size(), 1,
		"only the centred contender should place — every camp-1 anchor is unreachable under the floor")
	assert_push_warning("CenterCoreStarters")


# ── Acceptance 5 — the shipped preset still places the max roster ─────────
#
## Not a hand-built input on purpose (per the spec, this ONE acceptance test
## is explicitly about the authored `first_level.tres` preset surviving the
## non-degrading floor at max roster size: 2 humans + 12 AI, per
## `LobbyScreen.MAX_AI_OPPONENTS`). If this goes red, the floor is too
## aggressive for the authored `viability_radius` and that is the owner's
## number to adjust, not this test's to weaken.
##
## Two shapes, both real per `lobby_screen.gd`'s own docstring/comments — AI
## is always one shared camp (`_NPC_FACTION`), never split — so 2 humans +
## 12 AI is either coop (both humans on `camp_1`, `[2, 12]`) or versus (one
## human per camp, `[1, 1, 12]`). Versus has the most cross-camp pairs and is
## the stricter case for a non-degrading floor, so both are swept rather than
## just the coop shape.
const _CENTER_CORE_STARTERS_PATH := "res://procgen/placement/center_core_starters.tres"
const _FIRST_LEVEL_SHAPE_PATH := "res://procgen/modules/first_level/shape.tres"


func test_shipped_preset_places_the_max_roster() -> void:
	var shape: GraphProcgenShape = load(_FIRST_LEVEL_SHAPE_PATH)
	var mask: ShapeMask = shape.shape_mask
	var min_dist := 150.0 # 2 * node_radius(32) + node_padding(86), first_level.tres's topology
	var bounds := mask.aabb()
	var radius := 0.5 * minf(bounds.size.x, bounds.size.y)

	var shapes: Array[Array] = [[2, 12], [1, 1, 12]]
	for shape_sizes in shapes:
		var camp_sizes: Array[int] = []
		for n in shape_sizes:
			camp_sizes.append(n)
		var placement: CenterCoreStarters = (load(_CENTER_CORE_STARTERS_PATH) as CenterCoreStarters).duplicate(true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 909
		var pts := placement.plan(camp_sizes, radius, min_dist, rng, mask, 200)

		assert_eq(pts.size(), 14,
			"first_level.tres's authored CenterCoreStarters (viability_radius=%.1f) "
			% placement.viability_radius
			+ "must still place all 14 contenders (camp_sizes %s) under the non-degrading cross-camp floor"
			% str(camp_sizes))


# ── The camp lookup must follow the POINT, not the slot ──────────────────────
#
## `plan` compares each new candidate against every already-placed point, and
## asks `camp_of[j]` whether that point is a camp-mate — where `j` indexes the
## OUTPUT array. Those two indices agree only while nothing has been dropped.
##
## They can disagree: `test_crowded_map_warns_when_cross_camp_floor_is_
## unsatisfiable` above pins that an unplaceable contender is SKIPPED, not
## substituted, so the output is short. Once one slot is skipped, every later
## output index is offset from the participant index `camp_of` is keyed by —
## and a cross-camp pair can then be compared as if it were same-camp, which
## halves the floor #758 added expressly to stop an enemy opening on top of
## you. The point's own camp has to travel WITH the point.

func test_placed_points_carry_their_own_camp_through_a_skipped_slot() -> void:
	# camp_sizes [1, 1, 1, 1]: participants 0..3, each its own camp. If
	# participant 1 is skipped, output slot 1 holds participant 2 (camp 2)
	# while camp_of[1] still says camp 1 — so slot 2's cross-camp check
	# against it would read "same camp" and halve the required spacing.
	var lookup := CenterCoreStarters._camp_lookup([1, 1, 1, 1] as Array[int])
	assert_eq(lookup, [0, 1, 2, 3] as Array[int],
			"premise: camp_of is keyed by PARTICIPANT slot")

	var placement := CenterCoreStarters.new()
	placement.viability_radius = 3.0
	var mask := CircularShapeMask.new()
	mask.radius = 4000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pts := placement.plan([1, 1, 1, 1] as Array[int], 4000.0, _MIN_DIST, rng, mask, 200)

	# With room to spare nothing is skipped, so every returned point must be
	# able to name its own participant slot — the property that stays true
	# when something IS skipped.
	assert_eq(pts.size(), 4, "premise: a roomy mask places all four")
	for i in pts.size():
		assert_eq(placement.camp_of_placed(pts, i), lookup[i],
			"point %d must report the camp of the participant it belongs to" % i)


func test_camp_of_placed_follows_the_point_when_a_slot_is_skipped() -> void:
	# The direct statement of the invariant, without needing a geometry that
	# skips: a point knows its own camp, so a short array still answers right.
	var placement := CenterCoreStarters.new()
	var a := StartingPoint.new()
	var b := StartingPoint.new()
	placement._stamp_camp(a, 0)
	placement._stamp_camp(b, 2)   # participant 1 was skipped; this is camp 2
	var short_output: Array[StartingPoint] = [a, b]
	assert_eq(placement.camp_of_placed(short_output, 1), 2,
		"slot 1 of a SHORT array holds a camp-2 point — not camp_of[1]'s camp 1")
