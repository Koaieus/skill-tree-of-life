extends GutTest

## What one [method EntityCombat.snapshot] costs, on a real level, across the
## owned-node ramp — the number that decides whether gate-accurate AI scoring
## (#498 step 3) can afford a shadow per candidate.
##
## Run: [code]mise run test:one -- res://test/perf/bench_combat_snapshot.gd[/code]
##
## [b]Not collected by the suite.[/b] Same opt-out as
## `bench_allocation_cost.gd`: `.gutconfig.json` reads `res://test/unit/` only,
## and the `bench_` prefix keeps even `test:dir` from finding it.
##
## Fixture is deliberately the same shape as `bench_allocation_cost.gd`'s — real
## `first_level.tres` procgen at 2000 nodes, real [Entity], real
## [AllocationSystem] — because a snapshot's cost is dominated by what the node
## boards actually carry (minted borrowed stats, per-node modifiers), and a bare
## fixture has none of it.
##
## A snapshot is O(owned): one `StatBoard.clone_live()` for the entity board
## plus one `NodeStatBoard.clone_live()` per owned node, plus a
## [GraphMirror] `mirror_add` per node.
##
## Numbers move with the machine — record the CPU alongside any result you cite.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")

## North Star (docs/FOCUS.md): a 2000-node map at 144Hz. One frame's whole budget.
const _FRAME_BUDGET_USEC := 6944.0

const _NODE_COUNT := 2000
const _SEED := 0x57A17EE
const _CHECKPOINTS: Array[int] = [10, 50, 100, 200]
## Snapshots timed per checkpoint; median reported.
const _SAMPLES := 9

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _policy: AllocationPolicy
var _rng := RandomNumberGenerator.new()
var _built := false
var _samples: Dictionary = {}


func _ensure_fixture() -> void:
	if _built:
		return
	_built = true

	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.node_count = _NODE_COUNT
	cfg.seed = _SEED
	cfg.n_random_starters = 0

	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)

	var t_gen := Time.get_ticks_msec()
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	var gen_ms := Time.get_ticks_msec() - t_gen
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_false(starting_nodes.is_empty(), "procgen must return a starting node to spawn on")
	if starting_nodes.is_empty():
		return

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child(_alloc)

	_entity = _ENTITY_SCENE.instantiate() as Entity
	_entity.name = "BenchPlayer"
	_entity.display_name = "BenchPlayer"
	_entity.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, starting_nodes[0])
	_entity.core_location = starting_nodes[0]

	_policy = _POLICY.duplicate(true)
	_rng.seed = _SEED ^ 0x8EEDED
	_policy.rng = _rng

	gut.p("--- fixture: %s, node_count=%d, seed=0x%X, generated in %d ms ---"
		% [_PRESET.resource_path.get_file(), _graph.get_skill_nodes().size(), _SEED, gen_ms])


func after_all() -> void:
	for n in [_alloc, _graph]:
		if is_instance_valid(n):
			n.free()


func _owned_count() -> int:
	return _entity.navigator.get_mirrored_nodes().size()


func _frontier() -> Array[SkillNode]:
	var frontier: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {}
	for owned_node in _entity.navigator.get_mirrored_nodes():
		for neighbour in _graph.get_neighbours(owned_node):
			if neighbour.owned_by == null and not seen.has(neighbour):
				seen[neighbour] = true
				frontier.append(neighbour)
	return frontier


func _grow_to(target: int) -> void:
	while _owned_count() < target:
		var frontier := _frontier()
		if frontier.is_empty():
			return
		var pick: SkillNode = _policy.pick_next(_entity, frontier, null)
		if pick == null:
			return
		_alloc.force_allocate(_entity, pick)


func _median(times: Array[int]) -> float:
	if times.is_empty():
		return 0.0
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


## Median usec for a full [method EntityCombat.snapshot] + [method EntityCombat.free_shadow].
## The free is included on purpose: a caller CANNOT skip it (the shadow's
## backpointer cycle never reaches refcount 0 on its own), so it is part of what
## one rollout costs.
func _median_snapshot_usec() -> Dictionary:
	var totals: Array[int] = []
	var boards: Array[int] = []
	var live := _entity.get_combat()
	for i in _SAMPLES:
		var t := Time.get_ticks_usec()
		var shadow := live.snapshot()
		var elapsed := Time.get_ticks_usec() - t
		totals.append(elapsed)
		shadow.free_shadow()
	# Isolate the board-clone half: time clone_live() alone over the same set.
	for i in _SAMPLES:
		var t := Time.get_ticks_usec()
		var _b := _entity.stat_board.clone_live()
		for n in _entity.navigator.get_mirrored_nodes():
			n._init_node_board()
			var _nb := n.node_board.clone_live()
		boards.append(Time.get_ticks_usec() - t)
	return {"total": _median(totals), "boards": _median(boards)}


func test_snapshot_cost_ramp() -> void:
	await _ensure_fixture()

	gut.p("owned | snapshot+free (med) | board clones only | us/node | frames @144Hz")
	gut.p("------+---------------------+-------------------+---------+--------------")
	for target in _CHECKPOINTS:
		_grow_to(target)
		for i in 3:
			await get_tree().process_frame
		var owned := _owned_count()
		var m := _median_snapshot_usec()
		_samples[target] = {"owned": owned, "total": m["total"], "boards": m["boards"]}
		gut.p("%5d | %14.0f us | %14.0f us | %7.1f | %12.2f"
			% [owned, m["total"], m["boards"], m["total"] / maxf(1.0, float(owned)),
				m["total"] / _FRAME_BUDGET_USEC])

	var worst: Dictionary = _samples[_CHECKPOINTS[-1]]
	gut.p("")
	gut.p("at %d owned: 1 snapshot = %.2f frames; 50 = %.1f frames; 200 = %.1f frames"
		% [worst["owned"], worst["total"] / _FRAME_BUDGET_USEC,
			50.0 * worst["total"] / _FRAME_BUDGET_USEC,
			200.0 * worst["total"] / _FRAME_BUDGET_USEC])
	assert_eq(worst["owned"], _CHECKPOINTS[-1],
		"the ramp must reach its last checkpoint for the numbers above to mean anything")


## Where a node-board clone's time actually goes: the `Resource.duplicate(true)`
## (allocating a fresh Stat resource per field plus the inline
## `intrinsic_modifiers`) versus the bin-tally copy loop `clone_live` runs on
## top. Decides whether "copy the bins more cleverly" is even addressable.
func test_where_a_board_clone_spends_its_time() -> void:
	await _ensure_fixture()
	if _samples.is_empty():
		await test_snapshot_cost_ramp()

	var nodes := _entity.navigator.get_mirrored_nodes()
	var dup_times: Array[int] = []
	var full_times: Array[int] = []
	var ensure_times: Array[int] = []
	for n in nodes:
		n._init_node_board()
		var t := Time.get_ticks_usec()
		var raw: NodeStatBoard = n.node_board.duplicate(true)
		dup_times.append(Time.get_ticks_usec() - t)
		# The mint half alone: what _ensure_stat costs on a board whose
		# `_extra_stats` came back empty from duplicate().
		var t2 := Time.get_ticks_usec()
		for id in n.node_board.get_stat_ids():
			raw._ensure_stat(id)
		ensure_times.append(Time.get_ticks_usec() - t2)
		var t3 := Time.get_ticks_usec()
		var _live := n.node_board.clone_live()
		full_times.append(Time.get_ticks_usec() - t3)

	var dup := _median(dup_times)
	var ens := _median(ensure_times)
	var full := _median(full_times)
	gut.p("")
	gut.p("per NODE board, median over %d owned nodes:" % nodes.size())
	gut.p("  duplicate(true)          %7.1f us" % dup)
	gut.p("  _ensure_stat re-mint     %7.1f us" % ens)
	gut.p("  clone_live (whole thing) %7.1f us" % full)
	gut.p("  => bin-copy + base/current writes ~= %.1f us (%.0f%% of the clone)"
		% [full - dup - ens, 100.0 * (full - dup - ens) / maxf(1.0, full)])
	assert_gt(full, 0.0, "a board clone must be measurable at all")

	# The ENTITY board is cloned once per snapshot, not once per node — but it
	# carries ~40 typed Stat fields against a node board's sparse handful, so
	# it is worth knowing on its own.
	var ent_dup: Array[int] = []
	var ent_full: Array[int] = []
	for i in _SAMPLES:
		var t := Time.get_ticks_usec()
		var _raw: StatBoard = _entity.stat_board.duplicate(true)
		ent_dup.append(Time.get_ticks_usec() - t)
		var t2 := Time.get_ticks_usec()
		var _live: StatBoard = _entity.stat_board.clone_live()
		ent_full.append(Time.get_ticks_usec() - t2)
	gut.p("")
	gut.p("ENTITY board (once per snapshot):")
	gut.p("  duplicate(true)          %7.1f us" % _median(ent_dup))
	gut.p("  clone_live               %7.1f us" % _median(ent_full))
