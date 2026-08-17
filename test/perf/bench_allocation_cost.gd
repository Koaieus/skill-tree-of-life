extends GutTest

## What one allocation actually costs, on a real level, at North Star scale.
##
## Run: [code]mise run test:one -- res://test/perf/bench_allocation_cost.gd[/code]
##
## [b]Not collected by the suite.[/b] `.gutconfig.json` reads `res://test/unit/`
## only, so living in `test/perf/` is already the whole opt-out — no tag, no skip
## flag. The `bench_` prefix is a second layer: GUT only collects `test_*.gd`, so
## even `mise run test:dir -- res://test/perf/` finds nothing here and prints
## "Nothing was run". The explicit `test:one` path above is the way to run it.
## It costs ~10s of procgen before it measures anything; that is why.
##
## Unlike `test/unit/systems/test_vision_recompute_scaling.gd` — which builds a
## synthetic 45x45 grid to isolate one scaling property — this stands up the
## real thing: `first_level.tres` procgen at 2000 nodes, so every node carries
## the modifiers, addons, archetypes and spell grants a real run rolls, claimed
## by a real [Entity] through the shared [AllocationPolicy]. The point is that
## "allocate a node" costs what it costs *in the game*, not on a bare fixture.
##
## [b]It does NOT reproduce the reported framerate collapse.[/b] The 15fps@100 /
## 6fps@200-owned symptom is a per-frame repeater, and this fixture has no
## FogOverlay, no HUD and no VFX — the strongest lead is FogOverlay's
## per-element dimming walk (the #133 shape, O(elements x sources) every
## `vision_render_tick`). A green run here is not evidence that symptom is
## fixed. See lane P in docs/FOCUS.md.
##
## Numbers move with the machine — record the CPU alongside any result you cite.
##
## [b]First run, 2026-08-17[/b] (RX 7900 XTX box, headless). `force_allocate`
## itself is flat at ~620us regardless of owned count; the whole ramp lives in
## the vision recompute it triggers:
## [codeblock]
## owned | force_allocate | vision recompute
##    10 |         629 us |          3102 us
##    50 |         599 us |          3684 us
##   100 |         588 us |          5393 us
##   200 |         621 us |          9551 us
## [/codeblock]
## Per-phase attribution at 10 -> 200 owned (temporary instrumentation, not
## shipped — re-derive by timing the blocks of `VisionSystem._recompute` if you
## need it again):
## [codeblock]
## visibility pass        741 ->  4543 us   (6.1x — scales, see below)
## sensed walk            143 ->  1542 us   (10.8x)
## vision_range reads      31 ->   523 us
## rebind local stats      12 ->   224 us
## owned gather           247 ->   355 us
## node writes            700 ->   774 us   } ~2ms fixed floor,
## edge writes           1146 -> 1315 us   } independent of owned count
## [/codeblock]
## [b]The finding:[/b] the [VisionCircles] grid did not make the visibility pass
## owned-count-independent on a real level, only on the synthetic fixture. Its
## cell is one max-radius wide, so a cell holds roughly `(radius / spacing)^2`
## circles — at `first_level`'s 86px padding that is many, and it grows as
## territory densifies. `test_vision_recompute_scaling.gd` measured 1.75x for
## the same 25x owned increase because its grid is spaced 150px and its nodes
## carry no modifiers; that fixture is the best case, this one is the game.
## Shrinking the cell below max radius (multi-level grid, or bucket by radius)
## is the follow-up — lane P, not this file's job.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")

## North Star (docs/FOCUS.md): a 2000-node map at 144Hz. One frame's whole budget.
const _FRAME_BUDGET_USEC := 6944.0

const _NODE_COUNT := 2000
## Pinned so content — and therefore cost — is comparable across commits.
## Printed on every run; change it and you are benchmarking a different level.
const _SEED := 0x57A17EE
## Owned-node checkpoints. The ramp IS the complexity metric: a per-allocation
## cost that holds flat across these is the property the vision index bought.
const _CHECKPOINTS: Array[int] = [10, 50, 100, 200]

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _policy: AllocationPolicy
var _rng := RandomNumberGenerator.new()
var _built := false
## checkpoint -> {owned, alloc, frontier, recompute}, filled by the ramp test
## and read by the assertions so the 10s build happens exactly once.
var _samples: Dictionary = {}


# -- fixture ------------------------------------------------------------------

## Lazily built and shared by every test in this script. Deliberately not
## `before_all`: that would need an awaited coroutine there, and the whole
## fixture is ~10s of procgen we only ever want to pay once.
func _ensure_fixture() -> void:
	if _built:
		return
	_built = true

	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.node_count = _NODE_COUNT
	cfg.seed = _SEED
	# No AI starters: enemy territory would claim nodes out from under the
	# ramp and make "200 owned" depend on where the seeder happened to grow.
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

	# entity.tscn, not Entity.new(): _ready is what duplicates the stat board,
	# applies intrinsics and builds the EntityNavigator the mirror walks.
	_entity = _ENTITY_SCENE.instantiate() as Entity
	_entity.name = "BenchPlayer"
	_entity.display_name = "BenchPlayer"
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

	_policy = _POLICY.duplicate(true)
	_rng.seed = _SEED ^ 0x8EEDED
	_policy.rng = _rng

	gut.p("--- fixture: %s, node_count=%d, seed=0x%X, generated in %d ms ---"
		% [_PRESET.resource_path.get_file(), _graph.get_skill_nodes().size(), _SEED, gen_ms])


func after_all() -> void:
	# add_child, not add_child_autofree: the fixture has to outlive each test.
	# free(), not queue_free(): GUT's unfreed-children check runs before the
	# deferred queue drains, so queue_free leaves it warning about all of them.
	# Vision and alloc first — both hold references into the graph.
	for n in [_vision, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()


# -- measurement --------------------------------------------------------------

func _owned_count() -> int:
	return _entity.navigator.get_mirrored_nodes().size()


## Unowned nodes adjacent to owned territory. Same rule as
## `TerritorySeeder._frontier`, inlined here for one reason: the seeder times
## the walk and the claim together, and this bench needs them apart — the walk
## is O(owned x degree) per pick and would otherwise be misread as the cost of
## allocating.
func _frontier() -> Array[SkillNode]:
	var frontier: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {}
	for owned_node in _entity.navigator.get_mirrored_nodes():
		for neighbour in _graph.get_neighbours(owned_node):
			if neighbour.owned_by == null and not seen.has(neighbour):
				seen[neighbour] = true
				frontier.append(neighbour)
	return frontier


## Grows territory to `target` owned nodes as a greedy BFS ball — the same
## [AllocationPolicy] resource spawn seeding and the AI both pick with — timing
## every claim and every frontier walk individually.
##
## Returns `{alloc: median usec per force_allocate, frontier: median usec per walk}`.
func _grow_to(target: int) -> Dictionary:
	var alloc_times: Array[int] = []
	var frontier_times: Array[int] = []
	while _owned_count() < target:
		var t_f := Time.get_ticks_usec()
		var frontier := _frontier()
		frontier_times.append(Time.get_ticks_usec() - t_f)
		if frontier.is_empty():
			break
		var pick: SkillNode = _policy.pick_next(_entity, frontier, null)
		if pick == null:
			break
		var t_a := Time.get_ticks_usec()
		_alloc.force_allocate(_entity, pick)
		alloc_times.append(Time.get_ticks_usec() - t_a)
	return {"alloc": _median(alloc_times), "frontier": _median(frontier_times)}


## Median of several timed recomputes, in usec. Median rather than min so one
## unlucky sample can't pass a genuinely slow build, and rather than mean so a
## GC pause can't fail a fast one.
func _median_recompute_usec(samples: int = 7) -> float:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		_vision._recompute()
		times.append(Time.get_ticks_usec() - t)
	return _median(times)


func _median(times: Array[int]) -> float:
	if times.is_empty():
		return 0.0
	times.sort()
	return float(times[times.size() / 2])


# -- the bench ----------------------------------------------------------------

func test_allocation_cost_ramp() -> void:
	await _ensure_fixture()

	gut.p("owned | force_allocate | vision recompute | seeder frontier walk")
	gut.p("------+----------------+------------------+---------------------")
	for target in _CHECKPOINTS:
		var grown := await _grow_to(target)
		# Let the debounced deferred recompute the growth queued actually land,
		# so the timed passes below start from settled state rather than
		# absorbing the backlog into the first sample.
		for i in 3:
			await get_tree().process_frame
		var owned := _owned_count()
		var recompute := _median_recompute_usec()
		_samples[target] = {
			"owned": owned,
			"alloc": grown["alloc"],
			"frontier": grown["frontier"],
			"recompute": recompute,
		}
		gut.p("%5d | %10.0f us | %13.0f us | %16.0f us"
			% [owned, grown["alloc"], recompute, grown["frontier"]])

	var worst: Dictionary = _samples[_CHECKPOINTS[-1]]
	gut.p("")
	gut.p("at %d owned, one allocation settles in %.0f us = %.2f frames of the %.0f us 144Hz budget"
		% [worst["owned"], worst["alloc"] + worst["recompute"],
			(worst["alloc"] + worst["recompute"]) / _FRAME_BUDGET_USEC, _FRAME_BUDGET_USEC])
	assert_eq(worst["owned"], _CHECKPOINTS[-1],
		"the ramp must actually reach its last checkpoint for the numbers below to mean anything")


func test_recompute_cost_does_not_track_the_owned_count() -> void:
	await _ensure_fixture()
	if _samples.is_empty():
		await test_allocation_cost_ramp()

	var few: float = _samples[_CHECKPOINTS[0]]["recompute"]
	var many: float = _samples[_CHECKPOINTS[-1]]["recompute"]
	var owned_ratio := float(_CHECKPOINTS[-1]) / float(_CHECKPOINTS[0])
	var cost_ratio := many / maxf(few, 1.0)
	gut.p("recompute: %dx the owned nodes costs %.2fx" % [int(owned_ratio), cost_ratio])
	# Before VisionCircles' grid (a752739), the visibility pass was a per-point
	# linear scan over every owned circle and this tracked owned count almost
	# linearly (5.03x for 25x owned, measured by swapping the index back out).
	#
	# 4.0 is calibrated on THIS fixture, where 20x owned measured 3.08x — NOT on
	# `test_vision_recompute_scaling.gd`'s 3.0, which was calibrated on a
	# synthetic 150px grid with no node modifiers and does not transfer. The gap
	# between the two is the finding in this file's header, not slack: the
	# visibility pass alone is still 6.1x here. This guard catches losing the
	# index entirely; it does not certify the index is good enough.
	#
	# Caveat for whoever reads a pass here as reassurance: this ratio is diluted
	# by the recompute's owned-count-INDEPENDENT cost (~2ms of node + edge
	# writes). Add fixed work to `_recompute` and this guard gets EASIER to
	# pass. The ceiling below is what catches cost.
	assert_lt(cost_ratio, 4.0,
		"%dx the owned nodes must not cost anywhere near %dx the recompute" % [owned_ratio, owned_ratio])


func test_allocation_stays_within_a_catastrophe_ceiling() -> void:
	await _ensure_fixture()
	if _samples.is_empty():
		await test_allocation_cost_ramp()

	var worst: Dictionary = _samples[_CHECKPOINTS[-1]]
	var settled: float = worst["alloc"] + worst["recompute"]
	# Deliberately generous — this is a catastrophe guard, not a budget. The
	# pre-index regime was 19.4ms for the recompute alone; a machine several
	# times slower than the one this was written on still passes. If you want a
	# real budget, that conversation is `_FRAME_BUDGET_USEC` and lane P, and it
	# needs the per-frame repeater found first.
	assert_lt(settled, 25000.0,
		"one allocation at %d owned took %.0f us; the pre-index regime was ~19400 us for the recompute alone"
			% [worst["owned"], settled])
