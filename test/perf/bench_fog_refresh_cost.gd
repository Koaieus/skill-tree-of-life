extends GutTest

## The per-frame half of lane P: what [FogOverlay] costs on every
## `vision_render_tick`, at North Star scale.
##
## Run: [code]mise run test:one -- res://test/perf/bench_fog_refresh_cost.gd[/code]
## Same double exclusion as its siblings: outside `.gutconfig`'s `test/unit/`,
## and named `bench_` so GUT's `test_*.gd` collection skips it too.
##
## [b]Why this is the bench that matters for the reported symptom.[/b]
## `bench_allocation_cost.gd` measures a ONE-SHOT cost — what a single
## allocation costs, once. It cannot explain a framerate drop that persists for
## 5–10 seconds and then recovers, because a one-shot cost is one bad frame.
## This measures the repeater: [VisionSystem] emits `vision_render_tick` from
## `_process` for as long as any vision circle is animating toward its target
## radius, and each tick runs `FogOverlay._refresh` -> `set_sources`, which does
## two things whose cost scales with the level:
##
##   1. `VisionSourceIndex.build` — rebuilds the whole tile grid + GPU data
##      textures from scratch, O(sources).
##   2. `_apply_per_element_dimming` — walks EVERY SkillNode and EVERY Edge in
##      the graph, not just the visible ones. O(nodes + edges), independent of
##      how much is actually lit.
##
## Note (2) is the shape #133 already burned this project on once
## (O(elements × sources), 17–150 ms/frame, with the shader blamed and
## innocent). The `VisionSourceIndex` fix removed the × sources factor. The
## per-element walk itself was never removed, and at 2000 nodes it is paid every
## frame of every allocation's fade-in.
##
## [b]This is CPU only, and that is deliberate.[/b] The fragment shader cost
## needs real hardware — `scenes/overlay_perf_harness.gd` is the tool for that
## and says so. Everything measured here runs on the main thread in GDScript
## and is fully visible headless.
##
## [b]Result, 2026-08-17[/b] (RX 7900 XTX, headless; 2000 nodes, 3113 edges):
## [codeblock]
## owned | sources | set_sources | index build | per-element dimming | frames @144Hz
##    10 |      10 |     3444 us |       22 us |             3390 us |          0.50
##    50 |      50 |     5296 us |       72 us |             5210 us |          0.76
##   100 |     100 |    15097 us |      124 us |            14750 us |          2.17
##   200 |     200 |    78659 us |      230 us |            77764 us |         11.33
## [/codeblock]
##
## [b]This is the reported symptom.[/b] 78.7 ms per frame at 200 owned is ~12 fps,
## against a playtest report of 6 fps at 200 owned and 15 fps at 100 — the right
## magnitude, on the right axis, with the right persistence (it lasts exactly as
## long as the circle animation, then recovers). Note the shape: doubling owned
## from 100 to 200 costs 5.3x, not 2x.
##
## [b]It is entirely `_apply_per_element_dimming`[/b] — 99.7% at 200 owned. The
## index build is 230 us and innocent. The super-linear growth has two factors
## multiplying: more owned territory makes more nodes VISIBLE (only visible nodes
## take the expensive `distances_near` + fold branch), and it also packs more
## circles into each tile, so each fold is longer. So it is
## O(visible_nodes x circles_per_tile) and both terms rise together.
##
## Same root cause as the `VisionCircles` finding in `bench_allocation_cost.gd`:
## a tile whose cell is one (widened) max-radius wide holds many circles at
## `first_level`'s 86px node spacing. `VisionSourceIndex` removed #133's
## "x EVERY source" factor; it did not make the fold O(1), and the per-element
## walk over all 2000 nodes was never removed at all.
##
## Numbers move with the machine — record the CPU alongside any result you cite.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")
const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")

const _FRAME_BUDGET_USEC := 6944.0   ## 144Hz, the North Star.
const _NODE_COUNT := 2000
const _SEED := 0x57A17EE
const _OWNED_CHECKPOINTS: Array[int] = [10, 50, 100, 200]

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _fog: FogOverlay


func test_fog_refresh_cost_per_tick() -> void:
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.node_count = _NODE_COUNT
	cfg.seed = _SEED
	cfg.n_random_starters = 0

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
	_entity.name = "FogBenchPlayer"
	_entity.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, starting_nodes[0])
	_entity.core_location = starting_nodes[0]

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.allocation_system = _alloc
	_vision.viewers = [_entity]
	add_child(_vision)
	await get_tree().process_frame

	_fog = _FOG_SCENE.instantiate() as FogOverlay
	_fog.vision_system = _vision
	add_child(_fog)
	await get_tree().process_frame

	var policy: AllocationPolicy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	policy.rng = rng

	gut.p("graph: %d nodes, %d edges" % [_graph.get_skill_nodes().size(), _graph.get_edges().size()])
	gut.p("")
	gut.p("owned | sources | set_sources (median) | frames of 144Hz budget")
	gut.p("------+---------+----------------------+-----------------------")

	var worst := 0.0
	for target in _OWNED_CHECKPOINTS:
		_grow_to(target, policy)
		for i in 3:
			await get_tree().process_frame
		var sources: Array = _vision.get_vision_sources()
		var usec := _median_set_sources_usec(sources)
		worst = maxf(worst, usec)
		gut.p("%5d | %7d | %17.0f us | %21.2f"
			% [_owned(), sources.size(), usec, usec / _FRAME_BUDGET_USEC])

	gut.p("")
	gut.p("This cost is paid EVERY FRAME while any circle animates, not once per")
	gut.p("allocation. VisionSystem._process drives vision_render_tick until every")
	gut.p("circle reaches its target radius.")
	assert_gt(worst, 0.0, "the bench must have measured something")

	# THIS ASSERT IS EXPECTED TO FAIL TODAY. It is not a flaky bench — it is the
	# open defect, written down as a test that turns green when the defect is
	# fixed. Measured 78659 us against a 6944 us frame budget. Absolute rather
	# than a ratio because this is per-frame cost: a frame either fits or it
	# doesn't, and there is no owned-count scaling story that makes 78 ms fine.
	# 3x budget leaves room for a much slower machine while still catching the
	# #133 regime (17-150 ms/frame).
	assert_lt(worst, 3.0 * _FRAME_BUDGET_USEC,
		("KNOWN OPEN DEFECT (lane P), not a flaky bench: one fog refresh cost %.0f us "
			+ "against a %.0f us 144Hz frame budget, and it is paid EVERY frame while "
			+ "circles animate. See this file's header for the attribution.")
			% [worst, _FRAME_BUDGET_USEC])


## Median rather than mean so a GC pause can't dominate, and rather than min so
## an unlucky-but-real cost isn't discarded.
func _median_set_sources_usec(sources: Array, samples: int = 7) -> float:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		_fog.set_sources(sources)
		times.append(Time.get_ticks_usec() - t)
	times.sort()
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
	for n in [_fog, _vision, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()
