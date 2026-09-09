extends GutTest

## #782: what one [method MeleeAttackPlan.refresh_prediction] costs — the shadow
## resolve the melee preview now runs once per SELECTION CHANGE, on a real
## `first_level.tres` level at its shipped 800-node scale.
##
## Run: [code]mise run test:one -- res://test/perf/bench_melee_prediction_cost.gd[/code]
##
## [b]Not collected by the suite[/b] — same double opt-out as its siblings:
## `test/perf/` is outside `.gutconfig.json`'s `test/unit/`, and `bench_` keeps
## even `test:dir` from finding it.
##
## [b]Why this bench exists, and what changed under it.[/b] Before #782 the
## preview loop ran a full [method SkillBlade.simulate] EVERY ghost cycle —
## roughly once a second, forever, for as long as a selection was held — and
## resolved nothing. After #782 it simulates nothing and resolves once per
## selection change. So the number that matters moved: the steady-state cost of
## an idle preview went to approximately zero, and what is left is a per-CLICK
## hitch. #782's acceptance says measure it rather than assume it; this is that
## measurement.
##
## [b]The axes.[/b] Ramps BLADE SIZE, not defender territory. A melee resolve's
## work is (a) ~72 trajectory samples, each with an XPBD solve over the blade's
## own vertices and one [BladeHitScan] physics query per vertex and edge, and
## (b) the [CombatWorld] shadow snapshot of whatever it lands on — which since
## #695 is per NODE TOUCHED, not per node owned, and a swing touches a handful.
## Graph size used to enter through three O(total nodes) culling walks; #809
## and #811 removed all three, and running on the real 800-node level is what
## keeps that honest.
##
## Numbers move with the machine — record the CPU alongside any result you cite.
##
## [b]First run, 2026-09-09[/b] (RX 7900 XTX box, headless, GDScript solver —
## no native binary in this checkout). 800 nodes, 1235 edges, defender 100
## owned, attacker 12 owned:
## [codeblock]
## blade | vertices | refresh_prediction (med) |   worst | frames @144Hz (worst)
##     1 |        2 |                 8835 us | 10355 us |                 1.49
##     2 |        3 |                11409 us | 11447 us |                 1.65
##     3 |        4 |                13118 us | 13221 us |                 1.90
##     4 |        5 |                15774 us | 15901 us |                 2.29
## [/codeblock]
## Attribution at blade size 4 (`test_prediction_cost_attribution`):
## [codeblock]
## build_blade_state               1918 us (12.1%)
## build_swing_clock               1744 us (11.0%)
## build_obstacle_field            1701 us (10.7%)   <- inside build_blade_state
## collect_target_excludes          516 us ( 3.3%)
## CombatWorld.shadow() mint          3 us ( 0.0%)
## world.free_shadow()                1 us ( 0.0%)
## refresh_prediction (whole)     15864 us
## [/codeblock]
##
## [b]Verdict: acceptable, with a named follow-up.[/b] ~9-16 ms lands as a
## 1.5-2.3 frame hitch on a CLICK, and the identical resolve already runs on
## the COMMIT path ([method BattleSystem._compute_record]) — so this is not new
## work, it is the same work moved earlier, where a hitch is cheapest. Contrast
## #681, which found the same order of magnitude on a HOVER sweep and called it
## over budget: a hover fires per mouse-move and a click does not.
##
## What is worth fixing is the ~4.2 ms (26%) spent BEFORE the sim even starts —
## `build_blade_state` + `build_swing_clock` + `collect_target_excludes`, with
## `build_obstacle_field` already counted inside the first of those:
## [method MeleeAttackPlan.build_swing_clock] and
## [method MeleeAttackPlan.build_obstacle_field] each walk
## [method Graph.get_skill_nodes] — which rebuilds a typed array every call
## (`.claude/rules/graph.md`) — and [method MeleeAttackPlan.get_induced_edges]
## walks [method Graph.get_edges] the same way, all three O(total graph) to cull
## down to a handful of zones in blade reach. That is a spatial-index problem
## and it belongs to the whole melee path, commit included, not to the preview:
## filed as #807, which this bench's attribution test is the measurement for.
##
## [b]After #809, same machine, same day.[/b] #809 split two of those three
## O(total graph) walks out and fixed them: [method
## MeleeAttackPlan.get_induced_edges] now walks [method Graph.get_neighbours]
## (cached adjacency) over the selection instead of scanning every [Edge], and
## [method AttackPlan.collect_target_excludes] now starts from [member
## Entity.navigator]'s pre-built mirror plus each ally's, instead of filtering
## every [SkillNode]. [method MeleeAttackPlan.build_swing_clock] / [method
## MeleeAttackPlan.build_obstacle_field] are the still-open remainder — out of
## #809's scope on purpose, pending the sensing-model decision in #808:
## [codeblock]
## build_blade_state                                             1771-1800 us (11.6-11.7%)
##   ...of which build_obstacle_field                             1688-1761 us (11.1-11.3%)
##   ...of which everything else (get_induced_edges incl.)          39-84 us ( 0.2-0.5%)  <- was 217 us
## build_swing_clock                                             1719-1758 us (11.3%)      <- unchanged, #808
## build_obstacle_field                                          1688-1761 us (11.1%)      <- unchanged, #808
## collect_target_excludes                                          18 us  ( 0.1%)         <- was 516 us (29x)
## CombatWorld.shadow() mint                                       2-3 us  ( 0.0%)
## world.free_shadow()                                               1 us  ( 0.0%)
## refresh_prediction (whole)                                15202-15529 us
## [/codeblock]
## `get_induced_edges`'s own share of `build_blade_state` (i.e. `build_blade_state`
## minus the `build_obstacle_field` time it contains) dropped from 217 us to
## 39-84 us across runs; `collect_target_excludes` dropped from 516 us to a
## flat 18 us. `refresh_prediction (whole)` barely moves (15864 -> ~15200-15500
## us) because the two fixed walks were never its biggest cost —
## `build_swing_clock` / `build_obstacle_field` (#808) and the sim/scan/land
## interleave still dominate.
##
## [b]The 192x term, made visible (`test_coarse_pass_cost_at_192_proposals`).[/b]
## Neither this bench's own per-call attribution nor `bench_ai_turn.gd` (a
## 4-node fixture, where this is free) shows what [method
## AiBladeRollout._coarse_rank_and_select] actually pays on the shipped
## 800-node map: it calls [method MeleeAttackPlan.build_blade_state] + [method
## MeleeAttackPlan.build_drivers] on the CALLING thread, once per surviving
## proposal, up to `_MAX_PIVOTS (6) x _MAX_BLADE_SIZE_SAFETY (16) x 2
## directions` = 192 times, before any [WorkerThreadPool] task starts. At
## blade size 4, 192 repetitions measured 338495 us total — ~1763 us/proposal,
## ~49 frames @144Hz. That whole figure moves with #809's `build_blade_state`
## fix (the `get_induced_edges` share collapsed the same way per call above),
## but `build_swing_clock`'s equivalent is not measured here because
## `build_drivers` doesn't call it — the AI coarse pass never builds a swing
## clock at all, only [BladeSim.simulate]'s pure driver/state pair.
##
## [b]After #811, same machine, same day.[/b] The two O(map) zone walks are
## gone: one [method BladeDefenderZones.query] against #810's collision bits
## replaces both, and the rest-pose cull they shared (65% short, #808) is
## replaced by the generous chain-length whip bound. Same fixture, same seed:
## [codeblock]
## blade | vertices | refresh_prediction (med) |   worst | vs #809
##     1 |        2 |                 4866 us |  5763 us |  -45%
##     2 |        3 |                 7381 us |  7453 us |  -35%
##     3 |        4 |                 9168 us |  9233 us |  -30%
##     4 |        5 |                16098 us | 16420 us |   +2% (noise)
## [/codeblock]
## [codeblock]
## build_blade_state                                               135 us ( 0.8%)
##   ...of which build_defender_zones                               36 us ( 0.2%)   <- was 1688-1761
##   ...of which everything else (get_induced_edges incl.)          99 us ( 0.6%)
## build_defender_zones (one intersect_shape)                       36 us ( 0.2%)   <- replaces BOTH walks
## collect_target_excludes                                          13 us ( 0.1%)
## CombatWorld.shadow() mint                                         3 us ( 0.0%)
## world.free_shadow()                                               1 us ( 0.0%)
## refresh_prediction (whole)                                    16070 us
## [/codeblock]
## `build_swing_clock` (1719-1758 us) and `build_obstacle_field` (1688-1761 us)
## are gone from the attribution entirely — the methods no longer exist. What
## replaces them costs 36 us, ~96x less, and it is CORRECT where they were not.
##
## [b]Defender carriers on `first_level`[/b]
## (`test_defender_carrier_count_on_first_level`, #811 acceptance 5): 114 nodes
## carry `swing_drag`, 89 carry `deflection`, 18 carry both — 185 distinct
## carriers on an 800-node map, which is what
## [constant BladeDefenderZones._MAX_ZONES] (512) has to clear.
##
## [b]Blade size 4 is the whole story of that +2%.[/b] The whip bound is
## deliberately generous, so a size-4 blade on this map pulls dozens of zones
## into its field where the old rest-pose cull found a handful — and the field
## is walked per SOLVER ITERATION, not per sample. Measured naively that cost
## +29% (20414 us). [method BladeObstacleField.project]'s AABB broad phase —
## recomputed from the current pose every iteration, so it needs no safety
## margin — brings it back to noise. Keep that reject if you touch `project`.
##
## [b]The 192x term after #811.[/b] The coarse pass now issues ONE defender
## query per PIVOT and shares the immutable zone set across that pivot's
## proposals. Measured at 192 proposals, blade size 4: 12682 us shared vs
## 18447 us if every proposal queried for itself (the shape #811 refused) —
## and against 338495 us before #809. Note the coarse tier also GAINED
## fortification drag here, which it never had.
##
## The budget assert below is a REGRESSION catch, not the target: it is set well
## clear of the numbers above so it fires on a structural regression (the
## whole-subgraph shadow snapshot #695 removed coming back) rather than on
## machine-to-machine noise.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

const _FRAME_BUDGET_USEC := 6944.0   ## 144Hz, the North Star.
const _BUDGET_FRAMES := 4.0
const _SEED := 0x57A17EE
const _DEFENDER_OWNED := 100
const _ATTACKER_OWNED := 12
const _BLADE_SIZES: Array[int] = [1, 2, 3, 4]
const _SAMPLES := 5
const _MAX_FRONTIER_SEARCH := 400

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _frontline: SkillNode
var _built := false


func _ensure_fixture() -> void:
	if _built:
		return
	_built = true

	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating.
	cfg.topology = cfg.topology.duplicate(true)
	cfg.seed = _SEED
	cfg.camp_sizes = [2]

	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)

	var t_gen := Time.get_ticks_msec()
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	var gen_ms := Time.get_ticks_msec() - t_gen
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_true(starting_nodes.size() >= 2, "need a player core and an AI-starter core")
	if starting_nodes.size() < 2:
		return

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child(_alloc)

	_attacker = _ENTITY_SCENE.instantiate() as Entity
	_attacker.name = "BenchAttacker"
	_attacker.core_class = _CORE_CLASS
	_attacker.faction = _PLAYER_FACTION
	_graph.entities_container.add_child(_attacker)

	_defender = _ENTITY_SCENE.instantiate() as Entity
	_defender.name = "BenchDefender"
	_defender.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_defender)
	await get_tree().process_frame

	_alloc.force_allocate(_defender, starting_nodes[1])
	_defender.core_location = starting_nodes[1]

	var policy: AllocationPolicy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	policy.rng = rng
	_grow(_defender, _DEFENDER_OWNED, policy)

	_frontline = _find_frontline_node()
	assert_not_null(_frontline, "defender territory must border an unclaimed node")
	if _frontline == null:
		return
	_alloc.force_allocate(_attacker, _frontline)
	_attacker.core_location = _frontline
	# The attacker needs a real blob of its own: a blade is an induced subgraph
	# of OWNED territory, so a lone foothold could only ever swing one vertex.
	var attacker_policy: AllocationPolicy = _POLICY.duplicate(true)
	var arng := RandomNumberGenerator.new()
	arng.seed = _SEED ^ 0xB1ADE
	attacker_policy.rng = arng
	_grow(_attacker, _ATTACKER_OWNED, attacker_policy)

	# Bodies must exist before the hit scan queries them.
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	gut.p("--- fixture: %s, node_count=%d, edges=%d, seed=0x%X, generated in %d ms ---"
		% [_PRESET.resource_path.get_file(), _graph.get_skill_nodes().size(),
			_graph.get_edges().size(), _SEED, gen_ms])
	gut.p("defender owned: %d, attacker owned: %d, pivot on the frontline"
		% [_defender.navigator.get_mirrored_nodes().size(),
			_attacker.navigator.get_mirrored_nodes().size()])


func _find_frontline_node() -> SkillNode:
	for owned_node in _defender.navigator.get_mirrored_nodes():
		for neighbour in _graph.get_neighbours(owned_node):
			if neighbour.owned_by == null:
				return neighbour
	return null


func _frontier(entity: Entity) -> Array[SkillNode]:
	var frontier: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {}
	for owned_node in entity.navigator.get_mirrored_nodes():
		for neighbour in _graph.get_neighbours(owned_node):
			if neighbour.owned_by == null and not seen.has(neighbour):
				seen[neighbour] = true
				frontier.append(neighbour)
	return frontier


func _grow(entity: Entity, target: int, policy: AllocationPolicy) -> void:
	var guard := 0
	while entity.navigator.get_mirrored_nodes().size() < target and guard < _MAX_FRONTIER_SEARCH:
		guard += 1
		var frontier := _frontier(entity)
		if frontier.is_empty():
			return
		var pick: SkillNode = policy.pick_next(entity, frontier, null)
		if pick == null:
			return
		_alloc.force_allocate(entity, pick)


## A plan whose blade is `size` owned nodes BFS'd out from the frontline pivot —
## the shape a player builds by clicking outward from their border.
func _plan_of_size(size: int) -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _frontline
	var members: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {_frontline: true}
	var queue: Array[SkillNode] = [_frontline]
	while not queue.is_empty() and members.size() < size:
		var here: SkillNode = queue.pop_front()
		for neighbour in _graph.get_neighbours(here):
			if seen.has(neighbour) or neighbour.owned_by != _attacker:
				continue
			seen[neighbour] = true
			members.append(neighbour)
			queue.append(neighbour)
			if members.size() >= size:
				break
	plan.blade_nodes = members
	return plan


func after_all() -> void:
	for n in [_attacker, _defender, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()


func _median(times: Array[int]) -> float:
	if times.is_empty():
		return 0.0
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


## One `refresh_prediction()` per sample, on a FRESH plan each time so the cache
## is genuinely cold — which is what a selection change produces.
func test_prediction_cost_by_blade_size() -> void:
	await _ensure_fixture()
	if _frontline == null:
		return

	gut.p("")
	gut.p("blade | vertices | refresh_prediction (med) |   worst | frames @144Hz (worst)")
	gut.p("------+----------+--------------------------+---------+----------------------")

	var overall_worst := 0.0

	for size in _BLADE_SIZES:
		var probe := _plan_of_size(size)
		if probe.blade_nodes.size() < size:
			continue
		var samples: Array[int] = []
		var worst := 0.0
		for _s in _SAMPLES:
			var plan := _plan_of_size(size)
			var t := Time.get_ticks_usec()
			plan.refresh_prediction()
			var dt := Time.get_ticks_usec() - t
			assert_eq(plan.prediction_runs, 1, "one refresh must be one resolve")
			samples.append(dt)
			worst = maxf(worst, float(dt))
		overall_worst = maxf(overall_worst, worst)
		gut.p("%5d | %8d | %20.0f us | %5.0f us | %20.2f"
			% [size, probe.blade_nodes.size() + 1, _median(samples), worst,
				worst / _FRAME_BUDGET_USEC])

	gut.p("")
	assert_lt(overall_worst, _FRAME_BUDGET_USEC * _BUDGET_FRAMES,
		"one prediction must stay inside %.0f frames @144Hz — see the header: "
		% _BUDGET_FRAMES + "this line catches a structural regression, not noise")


## Where the time in one prediction actually goes, at the largest blade the ramp
## above measures. Attribution rather than a budget — no assert beyond the
## fixture guard, because the parts are not independently actionable.
##
## The interesting split is SOLVER vs. SCAN vs. SHADOW: the solver
## ([BladeSim.simulate_range]) is the part a native backend replaces, the scan
## ([BladeHitScan], one physics-server query per vertex and edge per sample) is
## not, and the shadow ([CombatWorld]) is the same lazy per-node snapshot #695
## measured for the spell preview.
func test_prediction_cost_attribution() -> void:
	await _ensure_fixture()
	if _frontline == null:
		return
	var size: int = _BLADE_SIZES[-1]
	var probe := _plan_of_size(size)
	if probe.blade_nodes.size() < size:
		return

	var build := 0
	var field_build := 0
	var excludes := 0
	var mint := 0
	var release := 0
	var whole := 0
	for _s in _SAMPLES:
		var plan := _plan_of_size(size)

		var t := Time.get_ticks_usec()
		var state := plan.build_blade_state()
		build += Time.get_ticks_usec() - t

		t = Time.get_ticks_usec()
		plan.build_defender_zones(state)
		field_build += Time.get_ticks_usec() - t

		t = Time.get_ticks_usec()
		plan.collect_target_excludes()
		excludes += Time.get_ticks_usec() - t

		t = Time.get_ticks_usec()
		var world := CombatWorld.shadow()
		mint += Time.get_ticks_usec() - t

		t = Time.get_ticks_usec()
		world.free_shadow()
		release += Time.get_ticks_usec() - t

		var fresh := _plan_of_size(size)
		t = Time.get_ticks_usec()
		fresh.refresh_prediction()
		whole += Time.get_ticks_usec() - t

	var n := float(_SAMPLES)
	gut.p("")
	gut.p("attribution at blade size %d (mean of %d):" % [size, _SAMPLES])
	for row in [
			["build_blade_state", build],
			["  ...of which build_defender_zones", field_build],
			["  ...of which everything else (get_induced_edges incl.)", build - field_build],
			["build_defender_zones (one intersect_shape)", field_build],
			["collect_target_excludes", excludes],
			["CombatWorld.shadow() mint", mint], ["world.free_shadow()", release]]:
		gut.p("  %-56s %7.0f us (%4.1f%%)"
			% [row[0], float(row[1]) / n, 100.0 * float(row[1]) / maxf(float(whole), 1.0)])
	gut.p("  %-56s %7.0f us" % ["refresh_prediction (whole)", float(whole) / n])
	gut.p("  the remainder is the sim/scan/land interleave itself — solver +")
	gut.p("  BladeHitScan queries + the shadow snapshot the landings force.")
	assert_gt(whole, 0, "the attribution run must have measured something")


## #809: [method AiBladeRollout._coarse_rank_and_select] builds a
## [BladeState] + driver set on the CALLING thread for every surviving
## proposal — up to `_MAX_PIVOTS (6) x _MAX_BLADE_SIZE_SAFETY (16) x 2
## directions` = 192 — before any [WorkerThreadPool] task starts. Neither
## `bench_ai_turn.gd` (a 4-node fixture, where this walk is free) nor the
## per-call attribution above (one call, not 192) makes that multiplier
## visible; this does, on the same 800-node level.
##
## Same two calls `_coarse_rank_and_select` makes per proposal
## ([method MeleeAttackPlan.build_blade_state], [method
## MeleeAttackPlan.build_drivers]), repeated 192 times at the largest blade
## size the ramp above measures — a stand-in for "worst pivot/size/direction
## count survives free rejection", not a claim that every AI turn hits it.
func test_coarse_pass_cost_at_192_proposals() -> void:
	await _ensure_fixture()
	if _frontline == null:
		return
	const _PROPOSAL_COUNT := 6 * 16 * 2  # _MAX_PIVOTS x _MAX_BLADE_SIZE_SAFETY x 2
	var size: int = _BLADE_SIZES[-1]
	var probe := _plan_of_size(size)
	if probe.blade_nodes.size() < size:
		return

	# (a) what the rollout actually does since #811: ONE defender query per
	#     pivot, shared across that pivot's proposals.
	var t := Time.get_ticks_usec()
	var shared := _plan_of_size(size).build_defender_zones(_plan_of_size(size).build_blade_state(
			BladeDefenderZones.new()))
	for _i in _PROPOSAL_COUNT:
		var plan := _plan_of_size(size)
		var state := plan.build_blade_state(shared)
		plan.build_drivers(state)
	var total := Time.get_ticks_usec() - t

	# (b) the same loop letting every proposal query for itself — the shape
	#     #811 explicitly refused ("do not issue 192 queries"). Kept measured
	#     so the sharing has a number attached rather than an argument.
	var t2 := Time.get_ticks_usec()
	for _i in _PROPOSAL_COUNT:
		var plan := _plan_of_size(size)
		var state := plan.build_blade_state()
		plan.build_drivers(state)
	var unshared := Time.get_ticks_usec() - t2

	gut.p("")
	gut.p("coarse-pass calling-thread cost at %d proposals, blade size %d:"
			% [_PROPOSAL_COUNT, size])
	gut.p("  %-56s %7.0f us" % ["total, ONE shared query (what #811 ships)", total])
	gut.p("  %-56s %7.2f us" % ["per proposal", float(total) / float(_PROPOSAL_COUNT)])
	gut.p("  %-56s %7.2f" % ["frames @144Hz", float(total) / _FRAME_BUDGET_USEC])
	gut.p("  %-56s %7.0f us" % ["total, a query PER proposal (refused)", unshared])
	assert_gt(total, 0, "the coarse-pass run must have measured something")


## The measurement #811's acceptance 5 asks for: how many nodes on the shipped
## `first_level` map actually carry each defender stat — i.e. how many
## colliders [method BladeDefenderZones.query] can ever return, which is what
## its `_MAX_ZONES` cap has to clear.
##
## Counted off the COLLISION BITS, not off the stat boards: that is what the
## query matches on, so this doubles as an end-to-end check that #810's
## registry actually reaches every carrier.
func test_defender_carrier_count_on_first_level() -> void:
	await _ensure_fixture()
	if _frontline == null:
		return
	var drag := 0
	var deflect := 0
	var both := 0
	var nodes := _graph.get_skill_nodes()
	for sn in nodes:
		var d := sn.get_collision_layer_value(SkillNode.DRAG_COLLISION_LAYER)
		var f := sn.get_collision_layer_value(SkillNode.DEFLECT_COLLISION_LAYER)
		if d:
			drag += 1
		if f:
			deflect += 1
		if d and f:
			both += 1
	gut.p("")
	gut.p("defender carriers on first_level (%d nodes):" % nodes.size())
	gut.p("  %-56s %7d" % ["swing_drag (Fortification)", drag])
	gut.p("  %-56s %7d" % ["deflection (Bunker)", deflect])
	gut.p("  %-56s %7d" % ["both", both])
	gut.p("  %-56s %7d" % ["BladeDefenderZones._MAX_ZONES cap", 512])
	assert_gt(nodes.size(), 0, "the carrier count run must have seen a map")

