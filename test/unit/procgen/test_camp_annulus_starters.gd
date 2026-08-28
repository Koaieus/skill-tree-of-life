extends GutTest

## Pins #551's camp-relative annulus starter placement: `plan()`'s geometry
## for all three arrangements (unit-level, no full generate needed), plus the
## integration guarantees that only a full [GraphProcgen.generate] pass can
## check — no anchor silently dropped by Poisson (which would shift every
## later participant onto the wrong node, see the issue body), and the
## `starter_placement == null` path stays byte-for-byte the old behaviour.

## Matches [GraphProcgenConfig]'s own defaults (`node_radius = 32`,
## `node_padding = 14`), so unit tests that call `plan()` directly still
## exercise the same clamp margin the shipped presets do.
const _MIN_DIST := 78.0
const _FIRST_LEVEL_PATH := "res://procgen/presets/first_level/first_level.tres"
const _COOP_VERSUS_PATH := "res://procgen/presets/coop_versus/coop_versus.tres"


# ── plan() geometry (items 1–6, 9's clamp half) ──────────────────────────


func test_grouped_camp_sizes_3_3() -> void:
	var placement := CampAnnulusStarters.new()
	placement.arrangement = CampAnnulusStarters.Arrangement.GROUPED
	var camp_sizes: Array[int] = [3, 3]
	# Large enough that the arc clamp (1.5 * _MIN_DIST) doesn't bind — this
	# test is about the unclamped GROUPED geometry; the clamp gets its own
	# tests below.
	var radius := 5000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pts := placement.plan(camp_sizes, radius, _MIN_DIST, rng)
	assert_eq(pts.size(), 6)

	var r_expected := placement.annulus_fraction * radius
	for sp in pts:
		assert_almost_eq(sp.position.length(), r_expected, 1.0)

	var camp0_angles := _angles_of(pts.slice(0, 3))
	var camp1_angles := _angles_of(pts.slice(3, 6))
	var spread0 := _angular_spread(camp0_angles)
	assert_true(spread0 <= placement.camp_arc_span + 0.01,
		"camp 0 spread %.4f exceeds arc span %.4f" % [spread0, placement.camp_arc_span])

	var mean0 := _circular_mean(camp0_angles)
	var mean1 := _circular_mean(camp1_angles)
	assert_almost_eq(absf(_angle_diff(mean0, mean1)), PI, 0.01)


func test_alternating_camp_sizes_3_3() -> void:
	var placement := CampAnnulusStarters.new()
	placement.arrangement = CampAnnulusStarters.Arrangement.ALTERNATING
	var camp_sizes: Array[int] = [3, 3]
	var radius := 1000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts := placement.plan(camp_sizes, radius, _MIN_DIST, rng)
	assert_eq(pts.size(), 6)
	_assert_evenly_spaced_and_alternating(pts, 6)


func test_random_camp_sizes_3_3() -> void:
	var placement := CampAnnulusStarters.new()
	placement.arrangement = CampAnnulusStarters.Arrangement.RANDOM
	var camp_sizes: Array[int] = [3, 3]
	var radius := 1000.0

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 99
	var pts_a := placement.plan(camp_sizes, radius, _MIN_DIST, rng_a)
	assert_eq(pts_a.size(), 6)
	var angles := _angles_of(pts_a)
	angles.sort()
	for i in angles.size():
		var a: float = angles[i]
		var b: float = angles[(i + 1) % angles.size()]
		var gap: float = _angle_diff(b, a) if i < angles.size() - 1 else _angle_diff(b + TAU, a)
		assert_almost_eq(gap, TAU / 6.0, 0.01)

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 99
	var pts_b := placement.plan(camp_sizes, radius, _MIN_DIST, rng_b)
	assert_eq(_position_key(pts_a), _position_key(pts_b), "same seed should give an identical assignment")

	var keys := {}
	for seed_val in [1, 2, 3, 4, 5]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		var pts := placement.plan(camp_sizes, radius, _MIN_DIST, rng)
		keys[_position_key(pts)] = true
	assert_gt(keys.size(), 1, "at least one of 5 seeds should give a different assignment")


func test_return_order_is_participant_order() -> void:
	var camp_sizes: Array[int] = [3, 3]
	var expected_ids := [
		"camp_0_member_0", "camp_0_member_1", "camp_0_member_2",
		"camp_1_member_0", "camp_1_member_1", "camp_1_member_2",
	]
	for arrangement in [
		CampAnnulusStarters.Arrangement.GROUPED,
		CampAnnulusStarters.Arrangement.ALTERNATING,
		CampAnnulusStarters.Arrangement.RANDOM,
	]:
		var placement := CampAnnulusStarters.new()
		placement.arrangement = arrangement
		var rng := RandomNumberGenerator.new()
		rng.seed = 13
		var pts := placement.plan(camp_sizes, 1000.0, _MIN_DIST, rng)
		var ids: Array = []
		for sp in pts:
			ids.append(String(sp.id))
		assert_eq(ids, expected_ids, "arrangement %d broke participant order" % arrangement)


func test_unequal_camps_3_1() -> void:
	var camp_sizes: Array[int] = [3, 1]
	for arrangement in [
		CampAnnulusStarters.Arrangement.GROUPED,
		CampAnnulusStarters.Arrangement.ALTERNATING,
		CampAnnulusStarters.Arrangement.RANDOM,
	]:
		var placement := CampAnnulusStarters.new()
		placement.arrangement = arrangement
		var rng := RandomNumberGenerator.new()
		rng.seed = 21
		var pts := placement.plan(camp_sizes, 1000.0, _MIN_DIST, rng)
		assert_eq(pts.size(), 4, "arrangement %d should place all 4 contenders" % arrangement)
		var positions := {}
		for sp in pts:
			positions[sp.position] = true
		assert_eq(positions.size(), 4, "arrangement %d: all 4 anchors should be distinct" % arrangement)


func test_arc_clamp_tiny_span_6_6() -> void:
	var placement := CampAnnulusStarters.new()
	placement.arrangement = CampAnnulusStarters.Arrangement.GROUPED
	placement.camp_arc_span = 0.001
	var camp_sizes: Array[int] = [6, 6]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pts := placement.plan(camp_sizes, 1000.0, _MIN_DIST, rng)
	assert_eq(pts.size(), 12)
	_assert_within_camp_spacing(pts, 1.5 * _MIN_DIST)


func test_arc_clamp_holds_under_pressure_8_8() -> void:
	var placement := CampAnnulusStarters.new()
	placement.arrangement = CampAnnulusStarters.Arrangement.GROUPED
	placement.camp_arc_span = 0.01
	var camp_sizes: Array[int] = [8, 8]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pts := placement.plan(camp_sizes, 1000.0, _MIN_DIST, rng)
	assert_eq(pts.size(), 16)
	_assert_within_camp_spacing(pts, 1.5 * _MIN_DIST)


# ── Full generate() integration (items 7, 8, 9's no-drop half, 10) ───────


func test_null_starter_placement_changes_nothing() -> void:
	var authored: GraphProcgenConfig = load(_FIRST_LEVEL_PATH)
	assert_null(authored.starting.starter_placement, "first_level.tres must not author a starter_placement")
	assert_true(authored.camp_sizes.is_empty(), "first_level.tres must not author camp_sizes")

	var cfg: GraphProcgenConfig = authored.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 60
	cfg.seed = 909
	var result := await _generate_full(cfg)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_eq(starting_nodes.size(), 1 + cfg.n_random_starters)
	assert_almost_eq((starting_nodes[0] as SkillNode).position, Vector2.ZERO, Vector2(0.5, 0.5))


func test_no_anchor_dropped() -> void:
	var shapes: Array[Array] = [[3, 3], [6, 6], [1]]
	var arrangements := [
		CampAnnulusStarters.Arrangement.GROUPED,
		CampAnnulusStarters.Arrangement.ALTERNATING,
		CampAnnulusStarters.Arrangement.RANDOM,
	]
	for shape in shapes:
		var camp_sizes: Array[int] = []
		for n in shape:
			camp_sizes.append(n)
		var total := 0
		for n in camp_sizes:
			total += n
		for arrangement in arrangements:
			var cfg := _minimal_config(camp_sizes, arrangement, 4242)
			var result := await _generate_full(cfg)
			var starting_nodes: Array = result.get("starting_nodes", [])
			var starters: Array = result.get("starters", [])
			assert_eq(starting_nodes.size(), total,
				"arrangement %d shape %s: expected %d starting nodes, got %d"
				% [arrangement, str(camp_sizes), total, starting_nodes.size()])
			for i in mini(starting_nodes.size(), starters.size()):
				var node_pos: Vector2 = (starting_nodes[i] as SkillNode).position
				var planned_pos: Vector2 = (starters[i] as StartingPoint).position
				assert_almost_eq(node_pos, planned_pos, Vector2(1.0, 1.0),
					"arrangement %d shape %s starter %d landed off its planned anchor"
					% [arrangement, str(camp_sizes), i])


func test_arc_clamp_no_drop_8_8() -> void:
	var camp_sizes: Array[int] = [8, 8]
	var cfg := _minimal_config(camp_sizes, CampAnnulusStarters.Arrangement.GROUPED, 11)
	(cfg.starting.starter_placement as CampAnnulusStarters).camp_arc_span = 0.01
	var result := await _generate_full(cfg)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_eq(starting_nodes.size(), 16, "no anchor should be dropped under a tiny authored arc span")


func test_integration_coop_versus_preset() -> void:
	var cfg: GraphProcgenConfig = (load(_COOP_VERSUS_PATH) as GraphProcgenConfig).duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 200
	cfg.seed = 555
	cfg.camp_sizes = [2, 2]
	var result := await _generate_full(cfg)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_eq(starting_nodes.size(), 4)
	var shape_mask: ShapeMask = cfg.shape.shape_mask
	var aabb := shape_mask.aabb()
	var r := 0.5 * minf(aabb.size.x, aabb.size.y)
	for n in starting_nodes:
		assert_gt((n as SkillNode).position.length(), 0.8 * r)


# ── Helpers ────────────────────────────────────────────────────────────────


func _minimal_config(camp_sizes: Array[int], arrangement: int, seed_val: int) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.seed = seed_val
	cfg.topology.node_count = 60
	cfg.topology.node_radius = 32.0
	cfg.topology.node_padding = 14.0
	cfg.shape.shape_mask = CircularShapeMask.new()
	var placement := CampAnnulusStarters.new()
	placement.arrangement = arrangement
	cfg.starting.starter_placement = placement
	cfg.camp_sizes = camp_sizes
	return cfg


func _generate_full(cfg: GraphProcgenConfig) -> Dictionary:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	return await GraphProcgen.generate(cfg, graph)


func _angles_of(pts: Array) -> Array[float]:
	var out: Array[float] = []
	for sp in pts:
		out.append((sp as StartingPoint).position.angle())
	return out


func _angle_diff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


func _angular_spread(angles: Array[float]) -> float:
	var base: float = angles[0]
	var min_d := 0.0
	var max_d := 0.0
	for a in angles:
		var d := _angle_diff(a, base)
		min_d = minf(min_d, d)
		max_d = maxf(max_d, d)
	return max_d - min_d


func _circular_mean(angles: Array[float]) -> float:
	var sx := 0.0
	var sy := 0.0
	for a in angles:
		sx += cos(a)
		sy += sin(a)
	return atan2(sy, sx)


func _camp_of(sp: StartingPoint) -> int:
	return int(String(sp.id).split("_")[1])


func _position_key(pts: Array) -> String:
	var key := ""
	for sp in pts:
		var p: Vector2 = (sp as StartingPoint).position
		key += "%.3f,%.3f;" % [p.x, p.y]
	return key


func _assert_evenly_spaced_and_alternating(pts: Array, n: int) -> void:
	var indexed: Array = []
	for sp in pts:
		indexed.append({"angle": (sp as StartingPoint).position.angle(), "camp": _camp_of(sp)})
	indexed.sort_custom(func(a, b): return a["angle"] < b["angle"])
	for i in indexed.size():
		var a: float = indexed[i]["angle"]
		var b: float = indexed[(i + 1) % indexed.size()]["angle"]
		var gap: float = _angle_diff(b, a) if i < indexed.size() - 1 else _angle_diff(b + TAU, a)
		assert_almost_eq(gap, TAU / float(n), 0.01)
	for i in indexed.size():
		var camp_a: int = indexed[i]["camp"]
		var camp_b: int = indexed[(i + 1) % indexed.size()]["camp"]
		assert_ne(camp_a, camp_b, "camp membership should alternate around the ring")


func _assert_within_camp_spacing(pts: Array, min_spacing: float) -> void:
	var by_camp: Dictionary = {}
	for sp in pts:
		var c := _camp_of(sp as StartingPoint)
		if not by_camp.has(c):
			by_camp[c] = []
		(by_camp[c] as Array).append(sp)
	for c in by_camp:
		var members: Array = by_camp[c]
		for i in range(members.size() - 1):
			var a: StartingPoint = members[i]
			var b: StartingPoint = members[i + 1]
			var d := a.position.distance_to(b.position)
			assert_true(d >= min_spacing - 0.5,
				"camp %d members %d,%d spaced %.2f < required %.2f" % [c, i, i + 1, d, min_spacing])


# ── #558 — a host-chosen arrangement, end to end ───────────────────────────
#
# #551 built the three arrangements; nothing exposed them. These pin the whole
# chain a lobby pick travels: RunConfig.overrides -> ScenarioOverride.merge_onto
# -> the duplicated `starting` module -> GraphProcgen -> the placed starters.
# Asserted on the PRODUCED starters, never by reading the field back — the
# issue exists to prevent "a dropdown that changes nothing observable".

const _COOP_VERSUS_SCENARIO_PATH := "res://session/scenarios/coop_versus.tres"
const _FIRST_LEVEL_SCENARIO_PATH := "res://session/scenarios/first_level.tres"


func _run_with_arrangement(scenario_path: String, arrangement: Variant) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.scenario = load(scenario_path) as Scenario
	cfg.seed = 313131
	if arrangement != null:
		var o := ScenarioOverride.new()
		o.target = "starting:starter_placement:arrangement"
		o.value = arrangement
		cfg.overrides = [o]
	return cfg


## Stamps the runtime-only inputs onto the MERGED preset. `topology` gets its
## own duplicate first: it is a top-level module `.tres` (an ExtResource), and
## `duplicate(true)` does not cross that boundary — the same trap
## `merge_onto`'s `_localize_module` exists for, arriving from the test side.
func _stamped(cfg_in: GraphProcgenConfig, camp_sizes: Array[int], seed_val: int) -> GraphProcgenConfig:
	var cfg := cfg_in
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 200
	cfg.seed = seed_val
	cfg.camp_sizes = camp_sizes
	return cfg


## #558 acceptance 1. A run carrying an ALTERNATING override against
## `coop_versus.tres` — whose authored value is GROUPED — produces starters that
## actually alternate around the annulus.
func test_an_arrangement_override_reaches_the_produced_starters() -> void:
	var run := _run_with_arrangement(
			_COOP_VERSUS_SCENARIO_PATH, CampAnnulusStarters.Arrangement.ALTERNATING)
	var camp_sizes: Array[int] = [3, 3]
	var cfg := _stamped(run.resolved_preset(), camp_sizes, run.seed)
	var result := await _generate_full(cfg)
	var starters: Array = result.get("starters", [])

	assert_eq(starters.size(), 6, "six starters were asked for")
	_assert_evenly_spaced_and_alternating(starters, 6)


## #558 acceptance 2. No override reproduces the preset's AUTHORED arrangement —
## D5's pinned default, GROUPED — asserted as clustered camps on opposite rims,
## which is the observable difference from the test above.
func test_no_override_reproduces_the_authored_grouped_arrangement() -> void:
	var run := _run_with_arrangement(_COOP_VERSUS_SCENARIO_PATH, null)
	assert_eq(run.overrides.size(), 0, "premise: nothing was picked")
	var camp_sizes: Array[int] = [3, 3]
	var cfg := _stamped(run.resolved_preset(), camp_sizes, run.seed)
	assert_eq(cfg.starting.starter_placement.arrangement,
			CampAnnulusStarters.Arrangement.GROUPED,
			"D5: the authored default stays GROUPED")

	var result := await _generate_full(cfg)
	var starters: Array = result.get("starters", [])
	assert_eq(starters.size(), 6)

	var camp0 := _angles_of(starters.slice(0, 3))
	var camp1 := _angles_of(starters.slice(3, 6))
	# Not bounded by the AUTHORED `camp_arc_span`: `_effective_arc_span` widens
	# it at runtime whenever the authored value would pack members closer than
	# `min_dist`, and on this preset's real radius it does. The bound that still
	# discriminates GROUPED from ALTERNATING is a quadrant — under ALTERNATING
	# with camps of 3 the same camp would span 4pi/3.
	assert_lt(_angular_spread(camp0), PI / 2.0,
			"GROUPED packs a camp into one arc rather than around the rim")
	assert_almost_eq(
			absf(_angle_diff(_circular_mean(camp0), _circular_mean(camp1))), PI, 0.01,
			"and puts the two camps on opposite rims")


## #558 acceptance 4, as the owner RESTATED it 2026-08-27 — the body's original
## "is unaffected and does not warn" inverted.
##
## `first_level.tres` authors no `starter_placement`, so
## `get_indexed("starting:starter_placement:arrangement")` on it returns `null`
## SILENTLY. Under #642 D14 that must not pass quietly: the merge warns, naming
## the unresolvable target, and the run still generates. A silent no-op here is
## exactly the "dropdown that changes nothing observable" symptom #558 exists to
## prevent. (No shipped route pairs this ladder with this preset —
## `test_lobby_roster.gd` pins that — but a mispaired one must be LOUD.)
func test_an_arrangement_override_on_a_placement_less_preset_warns_and_still_generates() -> void:
	var run := _run_with_arrangement(
			_FIRST_LEVEL_SCENARIO_PATH, CampAnnulusStarters.Arrangement.RANDOM)
	var authored: GraphProcgenConfig = load(_FIRST_LEVEL_PATH)
	assert_null(authored.starting.starter_placement,
			"premise: first_level.tres authors no starter_placement")

	var cfg := run.resolved_preset()
	assert_push_warning("starting:starter_placement:arrangement")
	assert_null(cfg.starting.starter_placement,
			"and nothing was conjured onto the preset")

	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 60
	cfg.seed = run.seed
	var result := await _generate_full(cfg)
	assert_gt((result.get("nodes", []) as Array).size(), 0,
			"the run still generates — a rejected override is never fatal")


## The module-mutation trap, from the consumer side: merging an arrangement
## override must not corrupt the authored `starting` module every later loader
## of `coop_versus.tres` shares.
func test_merging_an_arrangement_never_mutates_the_authored_module() -> void:
	var authored: GraphProcgenConfig = load(_COOP_VERSUS_PATH)
	var before: int = authored.starting.starter_placement.arrangement

	var run := _run_with_arrangement(
			_COOP_VERSUS_SCENARIO_PATH, CampAnnulusStarters.Arrangement.RANDOM)
	var merged := run.resolved_preset()
	assert_eq(merged.starting.starter_placement.arrangement,
			CampAnnulusStarters.Arrangement.RANDOM, "the copy took the override")
	assert_eq((load(_COOP_VERSUS_PATH) as GraphProcgenConfig)
			.starting.starter_placement.arrangement, before,
			"the authored module is byte-for-byte untouched")
