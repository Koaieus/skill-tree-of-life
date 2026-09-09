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
## Graph size enters only through the three O(total nodes) culling walks
## ([method MeleeAttackPlan.build_swing_clock],
## [method MeleeAttackPlan.build_obstacle_field],
## [method AttackPlan.collect_target_excludes]); running on the real 800-node
## level is what keeps those honest.
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
	var clock_build := 0
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
		plan.build_swing_clock(state)
		clock_build += Time.get_ticks_usec() - t

		t = Time.get_ticks_usec()
		plan.build_obstacle_field(state)
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
			["build_blade_state", build], ["build_swing_clock", clock_build],
			["build_obstacle_field", field_build], ["collect_target_excludes", excludes],
			["CombatWorld.shadow() mint", mint], ["world.free_shadow()", release]]:
		gut.p("  %-28s %7.0f us (%4.1f%%)"
			% [row[0], float(row[1]) / n, 100.0 * float(row[1]) / maxf(float(whole), 1.0)])
	gut.p("  %-28s %7.0f us" % ["refresh_prediction (whole)", float(whole) / n])
	gut.p("  the remainder is the sim/scan/land interleave itself — solver +")
	gut.p("  BladeHitScan queries + the shadow snapshot the landings force.")
	assert_gt(whole, 0, "the attribution run must have measured something")

