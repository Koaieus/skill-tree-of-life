extends GutTest

## What [AuraOverlay] costs per allocation signal, at North Star scale.
##
## Run: [code]mise run test:one -- res://test/perf/bench_aura_refresh_cost.gd[/code]
## Outside `.gutconfig`'s `test/unit/` and named `bench_`, like its siblings.
##
## `_refresh` walks EVERY SkillNode and EVERY Edge and rebuilds the tile index,
## so its one-shot cost is O(nodes + edges) and flat-ish in owned count — the
## same family as FogOverlay's ~2.6 ms classify (`bench_fog_refresh_cost.gd`).
## A one-shot is fine; a repeater is not. The repeater here was the burst: a
## synchronous run of allocation signals (a forced-dealloc cascade, a concede
## strip via `deallocate_all_owned`) paid one full walk PER LANDING in the
## same frame. The strip columns time that whole burst, frame flush included,
## with and without the aura listening; their difference is the aura's share.
##
## [b]FIXED — this bench is now a guard.[/b] Signal-driven refreshes coalesce
## to one deferred walk per frame. Ryzen 7 7800X3D, headless; 2000 nodes, 3104
## edges; the aura's share of one strip, before and after:
## [codeblock]
## owned | _refresh | strip, no aura | aura's share before | after
##    10 |  1257 us |        7238 us |            12014 us |  1016 us
##    50 |  1667 us |       36661 us |            70164 us |   653 us
##   100 |  2194 us |       75505 us |           172930 us |  1504 us
##   200 |  3257 us |      158032 us |           430973 us | 13264 us
## [/codeblock]
## "after" is one walk plus frame noise (the share is a difference of two
## frame-flush timings; a rerun read 0 us at 200). The no-aura column is AllocationSystem's own ~0.8 ms
## per forced deallocate — real, but not the overlay's, and not judged here.
##
## CPU only — the fragment cost needs real hardware
## (`scenes/overlay_perf_harness.gd`). Numbers move with the machine; record
## the CPU alongside any result you cite.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")
const _AURA_SCENE := preload("res://ui/aura_overlay/aura_overlay.tscn")

const _FRAME_BUDGET_USEC := 6944.0   ## 144Hz, the North Star.
const _NODE_COUNT := 2000
const _SEED := 0x57A17EE
const _OWNED_CHECKPOINTS: Array[int] = [10, 50, 100, 200]

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _aura: AuraOverlay
var _start: SkillNode


func test_aura_refresh_cost() -> void:
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
	cfg.seed = _SEED
	# Starters are placed per camp; one camp of one is the single bench player.
	cfg.camp_sizes = [1]

	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_false(starting_nodes.is_empty(), "procgen must return a starting node")
	if starting_nodes.is_empty():
		return
	_start = starting_nodes[0]

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child(_alloc)
	_entity = _ENTITY_SCENE.instantiate() as Entity
	_entity.name = "AuraBenchPlayer"
	_entity.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _start)
	_entity.core_location = _start

	_aura = _AURA_SCENE.instantiate() as AuraOverlay
	_aura.graph = _graph
	_aura.allocation_system = _alloc
	add_child(_aura)
	await get_tree().process_frame

	var policy: AllocationPolicy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	policy.rng = rng

	gut.p("graph: %d nodes, %d edges" % [_graph.get_skill_nodes().size(), _graph.get_edges().size()])
	gut.p("")
	gut.p("owned | _refresh (median) | strip, no aura | strip, aura | aura's share")
	gut.p("------+-------------------+----------------+-------------+-------------")

	var worst_share := 0.0
	var refresh_usec_seen := 0.0
	for target in _OWNED_CHECKPOINTS:
		_grow_to(target, policy)
		await get_tree().process_frame
		var refresh_usec := _median_refresh_usec()
		refresh_usec_seen = maxf(refresh_usec_seen, refresh_usec)
		var owned := _owned()
		_aura.allocation_system = null
		var bare_usec := await _burst_usec()
		_aura.allocation_system = _alloc
		var burst_usec := await _burst_usec()
		var share := maxf(burst_usec - bare_usec, 0.0)
		worst_share = maxf(worst_share, share)
		gut.p("%5d | %14.0f us | %11.0f us | %8.0f us | %8.0f us"
			% [owned, refresh_usec, bare_usec, burst_usec, share])

	assert_gt(refresh_usec_seen, 0.0, "the bench must have measured something")
	# One walk per burst is a few ms at 2000 nodes; one walk per landing was
	# owned x that (~430 ms at 200 owned). The strip's own cost, no aura
	# mounted, is AllocationSystem's and is not this bench's to judge.
	# 10x budget: the share is a noisy difference, and 430 ms still trips it 6x.
	assert_lt(worst_share, 10.0 * _FRAME_BUDGET_USEC,
		"the aura's share of one territory strip was %.0f us — it is walking the graph per landing again"
			% worst_share)


func _median_refresh_usec(samples: int = 5) -> float:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		_aura._refresh()
		times.append(Time.get_ticks_usec() - t)
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


## Strip every owned node in one synchronous burst and time it through the
## next frame — a deferred refresh lands in the flush at the end of the burst's
## frame, so the wait is where a coalesced walk is paid. An idle frame is
## subtracted so the number is the burst, not the frame loop. The territory is
## then restored untimed and flushed so the next checkpoint starts clean.
func _burst_usec() -> float:
	var idle := await _frame_usec()
	var owned: Array[SkillNode] = []
	for sn in _entity.navigator.get_mirrored_nodes():
		owned.append(sn)
	var t := Time.get_ticks_usec()
	_alloc.deallocate_all_owned(_entity)
	await get_tree().process_frame
	var usec := maxf(float(Time.get_ticks_usec() - t) - idle, 0.0)
	_alloc.force_allocate(_entity, _start)
	_entity.core_location = _start
	for sn in owned:
		if sn.owned_by == null:
			_alloc.force_allocate(_entity, sn)
	await get_tree().process_frame
	return usec


func _frame_usec() -> float:
	await get_tree().process_frame
	var t := Time.get_ticks_usec()
	await get_tree().process_frame
	return float(Time.get_ticks_usec() - t)


func _owned() -> int:
	return _entity.navigator.get_mirrored_nodes().size()


func _grow_to(target: int, policy: AllocationPolicy) -> void:
	while _owned() < target:
		var frontier := _frontier()
		if frontier.is_empty():
			return
		var pick: SkillNode = policy.pick_next(_entity, frontier, null)
		if pick == null:
			return
		_alloc.force_allocate(_entity, pick)


func _frontier() -> Array[SkillNode]:
	var frontier: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {}
	for owned_node in _entity.navigator.get_mirrored_nodes():
		for neighbour in _graph.get_neighbours(owned_node):
			if neighbour.owned_by == null and not seen.has(neighbour):
				seen[neighbour] = true
				frontier.append(neighbour)
	return frontier


func after_all() -> void:
	for n in [_aura, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()
