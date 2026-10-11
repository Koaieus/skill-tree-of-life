extends GutTest

## One [LanternLayer] frame at North Star scale, printed next to the number it
## has to beat: one [method FogOverlay.set_sources] at 200 sources, which is
## `bench_fog_refresh_cost.gd`'s worst row and the whole per-frame fog cost.
##
## Run: [code]mise run test:one -- res://test/perf/bench_lantern_frame.gd[/code]
## Outside `.gutconfig`'s dirs and named `bench_`, like its siblings.
##
## A lantern frame is: collect + camp-filter the group, write the N x 1 disc
## texture, then the lit pass — lanterns x the nodes in the static grid cells
## each disc covers, never a walk over the graph. CPU only; the per-pixel lantern
## loop in every vision-field consumer needs real hardware
## (`scenes/overlay_perf_harness.gd`).
##
## [b]Result[/b] (AMD Ryzen 7 7800X3D 8-Core Processor, headless; 3000 nodes, 200 owned,
## 200 sources, radius 120): a lantern frame is CHEAPER than the set_sources it
## sits beside even at the 64 cap, and is paid only while lanterns exist.
## [codeblock]
## set_sources @ 200 sources: 351 us
## lanterns | lit nodes | lantern frame | vs set_sources
##       10 |        10 |         44 us |          0.13x
##       64 |        63 |        304 us |          0.87x
## [/codeblock]
## Linear in lanterns (~4.7 us each, the camp filter's `_effective_viewers`
## call included); the static grid keeps the node term local.
##
## Numbers move with the machine — record the CPU alongside any result you cite.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")
const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")
const _LANTERN_SCENE := preload("res://ui/fog_overlay/lantern.tscn")

const _FRAME_BUDGET_USEC := 6944.0   ## 144Hz, the North Star.
const _NODE_COUNT := 3000
const _OWNED := 200
const _SEED := 0x1A7E2
const _LANTERN_CHECKPOINTS: Array[int] = [10, 64]

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _fog: FogOverlay
var _layer: LanternLayer
var _lanterns: Array[Lantern] = []


func test_lantern_frame_cost() -> void:
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
	cfg.seed = _SEED
	cfg.camp_sizes = [1]
	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_false(starting_nodes.is_empty(), "procgen must return a starting node")
	if starting_nodes.is_empty():
		return

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child(_alloc)
	_entity = _ENTITY_SCENE.instantiate() as Entity
	_entity.name = "LanternBenchPlayer"
	_entity.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, starting_nodes[0])
	_entity.core_location = starting_nodes[0]
	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.allocation_system = _alloc
	_vision.viewers = [_entity]
	_vision.ease_rate = 0.0
	add_child(_vision)
	_fog = _FOG_SCENE.instantiate() as FogOverlay
	_fog.vision_system = _vision
	add_child(_fog)
	_layer = _fog.get_node(^"LanternLayer") as LanternLayer
	var policy: AllocationPolicy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	policy.rng = rng
	_grow_to(_OWNED, policy)
	for i in 3:
		await get_tree().process_frame

	var sources: Array = _vision.get_vision_sources()
	var set_sources_usec := _median_usec(func() -> void: _fog.set_sources(sources))
	# Lanterns sit on fogged nodes, so the lit pass has real work to do.
	var fogged: Array[SkillNode] = []
	for n in _graph.get_skill_nodes():
		if not n.revealed:
			fogged.append(n)
	gut.p("graph: %d nodes; %d owned, %d vision sources, %d fogged"
		% [_graph.get_skill_nodes().size(), _owned(), sources.size(), fogged.size()])
	gut.p("set_sources @ %d sources: %.0f us" % [sources.size(), set_sources_usec])
	gut.p("lanterns | radius | lit nodes | lantern frame (median) | vs set_sources")
	var worst := 0.0
	for count in _LANTERN_CHECKPOINTS:
		_place_lanterns(count, fogged, rng)
		await get_tree().process_frame
		var usec := _median_usec(func() -> void: _layer._process(1.0 / 144.0))
		worst = maxf(worst, usec)
		var lit := 0
		for n in fogged:
			if n.lantern_lit:
				lit += 1
		gut.p("%8d | %6.0f | %9d | %19.0f us | %13.2fx"
			% [count, _lanterns[0].radius, lit, usec, usec / maxf(set_sources_usec, 1.0)])
	assert_gt(worst, 0.0, "the bench must have measured something")
	assert_lt(worst, _FRAME_BUDGET_USEC, "one lantern frame must fit a 144Hz frame")


func _place_lanterns(count: int, fogged: Array[SkillNode], rng: RandomNumberGenerator) -> void:
	while _lanterns.size() < count:
		var l := _LANTERN_SCENE.instantiate() as Lantern
		l.source = _entity
		add_child(l)
		l.global_position = fogged[rng.randi_range(0, fogged.size() - 1)].global_position
		_lanterns.append(l)


func _median_usec(fn: Callable, samples: int = 9) -> float:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		fn.call()
		times.append(Time.get_ticks_usec() - t)
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


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
	for n in _lanterns + [_fog, _vision, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()
