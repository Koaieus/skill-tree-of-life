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
##   2. (until #414) `_apply_per_element_dimming` — walked EVERY SkillNode and
##      EVERY Edge in the graph, not just the visible ones. O(nodes + edges),
##      independent of how much is actually lit. It is gone from this path; see
##      the result block below.
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
## [b]FIXED by #414 — this bench is now a guard, not a defect report.[/b]
## RX 7900 XTX, headless; 2000 nodes, 3113 edges. `set_sources` is the whole
## per-frame path; the second column is what it used to cost:
## [codeblock]
## owned | sources | set_sources | before #414 | frames @144Hz | classify
##    10 |      10 |       31 us |     3444 us |          0.00 |  2672 us
##    50 |      50 |       67 us |     5296 us |          0.01 |  2659 us
##   100 |     100 |      115 us |    15097 us |          0.02 |  2657 us
##   200 |     200 |      209 us |    78659 us |          0.03 |  2614 us
## [/codeblock]
##
## Read the last column as the shape of the win, not just its size: the
## classification pass is FLAT in owned count (~2.6 ms, the pure walk over 2000
## nodes + 3113 edges) because the O(visible x circles_per_tile) term is gone
## outright, and it is paid once per allocation rather than once per frame.
## 2.6 ms once is a fair next target (#439 is the family) — 78 ms every frame
## was not survivable.
##
## What was left is `VisionSourceIndex.build`, which was always innocent
## (230 us at 200 sources, 3% of a 144Hz frame). What went away is the
## O(elements) per-element pass: SkillNode's disk and rim now self-shade
## per-fragment against the shared `vision_field` globals (#414), exactly as
## edges already did (#413), so nothing samples fog darkness on the CPU, and
## the visible/sensed/hidden CLASSIFICATION that remains hangs off
## `visibility_changed` — once per allocation — instead of every frame. It can,
## because [VisionSystem] computes logical visibility from TARGET radii: a
## circle animating toward its target changes which pixels are lit, never which
## nodes are visible.
##
## [b]The historical numbers, kept because they are the diagnosis.[/b] 78.7 ms
## per frame at 200 owned is ~12 fps, against a playtest report of 6 fps at 200
## owned and 15 fps at 100 — right magnitude, right axis, right persistence (it
## lasted exactly as long as the circle animation, then recovered). 99.7% of it
## was `_apply_per_element_dimming`, and it grew super-linearly (100 -> 200 owned
## cost 5.3x, not 2x) because two terms rose together: more owned territory makes
## more nodes VISIBLE (only visible nodes took the expensive `distances_near` +
## fold branch), and it packs more circles into each tile, so each fold was
## longer — O(visible_nodes x circles_per_tile).
##
## Same root cause as the `VisionCircles` finding in `bench_allocation_cost.gd`:
## a tile whose cell is one (widened) max-radius wide holds many circles at
## `first_level`'s 86px node spacing. `VisionSourceIndex` removed #133's
## "x EVERY source" factor; it did not make the fold O(1), and the per-element
## walk over all 2000 nodes was never removed at all until #414 deleted it.
##
## [b]What this bench cannot see.[/b] It times `set_sources`, so a walk that
## merely MOVED somewhere untimed would also make this number drop.
## `test/unit/ui/test_fog_overlay_classification.gd` pins the structural half —
## which signal each pass hangs off — and the two are meant to be read together.
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
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
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
	gut.p("owned | sources | set_sources (median) | frames of 144Hz budget | classify")
	gut.p("------+---------+----------------------+------------------------+---------")

	var worst := 0.0
	for target in _OWNED_CHECKPOINTS:
		_grow_to(target, policy)
		for i in 3:
			await get_tree().process_frame
		var sources: Array = _vision.get_vision_sources()
		var usec := _median_set_sources_usec(sources)
		worst = maxf(worst, usec)
		gut.p("%5d | %7d | %17.0f us | %22.2f | %6.0f us"
			% [_owned(), sources.size(), usec, usec / _FRAME_BUDGET_USEC,
				_median_classify_usec()])

	gut.p("")
	gut.p("set_sources is paid EVERY FRAME while any circle animates:")
	gut.p("VisionSystem._process drives vision_render_tick until every circle")
	gut.p("reaches its target radius. The classify column is the O(elements)")
	gut.p("pass, and it is paid ONCE PER ALLOCATION (visibility_changed) — it is")
	gut.p("reported here to keep it honest, not because it sits in the frame.")
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
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


## The O(elements) half, on its own signal. Not part of `worst` — this one is
## allowed to be expensive, it runs once per allocation, not once per frame.
func _median_classify_usec(samples: int = 5) -> float:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		_fog._apply_visibility_classification()
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
	for n in [_fog, _vision, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()
