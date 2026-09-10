extends GutTest

## #796 item 2 (MEASURE AND REPORT ONLY, not build) — what the AUTHORITY's own
## `BattleSystem._compute_record` pays for a k=50 swing near defenders, on the
## real 800-node `first_level.tres` scale. The question this answers: is the
## authority's own resolve still a scheduling problem after #813 landed the
## native backend's defender-field support, or was that the whole fix?
##
## Fixture is `bench_melee_prediction_cost.gd`'s, duplicated rather than
## imported (that file owns blade sizes 1-4 and this one needs a much bigger
## attacker territory to host a 50-vertex blade) — same seed, same defender
## count, same `greedy_bfs_ball` policy, so the two are directly comparable.
##
## Solver + hit-scan TOGETHER, unlike `bench_blade_sim.gd` (solver only,
## headless `SceneTree`, no physics) — this runs in a real scene with a real
## `PhysicsDirectSpaceState2D`, which is what `MeleeAttackPlan.resolve_against`
## actually calls through `BladeHitScan.scan`. That is the number a frame
## stall is actually made of.
##
## Numbers move with the machine — record the CPU alongside any result you
## cite. This box is a Ryzen 7 7800X3D + RX 7900 XTX, near the top of the
## single-thread range a weak machine sits nowhere near — every local timing
## below is best-case.
##
## [b]2026-09-10, this checkout, GDScript backend[/b] (no native `.so` built
## here — `native/godot-cpp` is an uninitialized submodule in this worktree,
## and fetching + building it was out of scope for a measure-and-report ask).
## k=51 (50 blade nodes BFS'd out from the frontline + the pivot), near 100
## real defender-owned nodes on the shipped 800-node level:
## [codeblock]
## median: 955.8 ms   worst: 961.0 ms
## [/codeblock]
## This is `resolve_against` WHOLE — solver, hit-scan, shadow build and land,
## not solver alone — against a BFS-grown blob rather than a synthetic
## whip/mesh, so it is not directly comparable to `bench_blade_sim.gd`'s
## k=100 rows (596.8 ms braced-mesh / 251.2 ms whip, solver only, GDScript).
## It reads high for its k because a `greedy_bfs_ball` shape is denser
## (more constraints per vertex) than either synthetic shape.
##
## Applying the issue's own same-machine native/GDScript ratio (#796 comment
## 2026-09-09: 22.1x braced-mesh / 15.9x whip, solver-only) to the 961 ms
## worst case gives an ESTIMATED — not directly measured — native worst case
## of roughly 44-60 ms, and a Tier L extrapolation (x2-3) of roughly 88-180 ms.
## That lands in the same range the issue's last comment already called "one
## staging beat's worth of masking, not a time-slicing problem" at k=100. See
## the issue thread for the recommendation this measurement feeds.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

const _SEED := 0x57A17EE
const _DEFENDER_OWNED := 100
## Big enough to host a 50-node blade BFS'd out from the frontline — #796's
## acceptance names k=50 specifically.
const _ATTACKER_OWNED := 90
const _BLADE_SIZE := 50
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
	cfg.topology = cfg.topology.duplicate(true)
	cfg.seed = _SEED
	cfg.camp_sizes = [2]

	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)

	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
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
	var attacker_policy: AllocationPolicy = _POLICY.duplicate(true)
	var arng := RandomNumberGenerator.new()
	arng.seed = _SEED ^ 0xB1ADE
	attacker_policy.rng = arng
	_grow(_attacker, _ATTACKER_OWNED, attacker_policy)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	gut.p("--- fixture: %s, node_count=%d, edges=%d, seed=0x%X, backend=%s ---"
		% [_PRESET.resource_path.get_file(), _graph.get_skill_nodes().size(),
			_graph.get_edges().size(), _SEED, BladeSim.backend()])
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


## The exact call `BattleSystem._compute_record` makes: `resolve_against` a
## throwaway shadow — solver, hit-scan and land, all of it, on whichever
## backend `BladeSim.backend()` reports above.
func test_authoritative_resolve_cost_at_k50_near_defenders() -> void:
	await _ensure_fixture()
	if _frontline == null:
		return
	var probe := _plan_of_size(_BLADE_SIZE)
	gut.p("blade requested k=%d, actually reachable=%d" % [_BLADE_SIZE, probe.blade_nodes.size()])
	if probe.blade_nodes.size() < _BLADE_SIZE / 2:
		gut.p("fixture could not grow a blade anywhere near k=%d — skipping" % _BLADE_SIZE)
		return

	var samples: Array[int] = []
	var worst := 0
	for _s in _SAMPLES:
		var plan := _plan_of_size(_BLADE_SIZE)
		var world := CombatWorld.shadow()
		var t := Time.get_ticks_usec()
		plan.resolve_against(world)
		var dt := Time.get_ticks_usec() - t
		world.free_shadow()
		samples.append(dt)
		worst = maxi(worst, dt)

	gut.p("")
	gut.p("k=%d authoritative resolve_against (solver+hitscan+land), %s backend:"
		% [probe.blade_nodes.size() + 1, BladeSim.backend()])
	gut.p("  median: %.1f ms   worst: %.1f ms" % [_median(samples) / 1000.0, worst / 1000.0])
	gut.p("  Tier L extrapolation (x2-3, comment-3 methodology): %.0f-%.0f ms"
		% [worst / 1000.0 * 2.0, worst / 1000.0 * 3.0])
