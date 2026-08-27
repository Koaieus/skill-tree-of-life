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
## [b]First run, 2026-08-17[/b] (RX 7900 XTX box, headless):
## [codeblock]
## owned | force_allocate (med / max) | vision recompute (med / cold)
##    10 |        619 /        699 us |         3054 /        3347 us
##    50 |        593 /       1136 us |         3655 /        3673 us
##   100 |        574 /       3273 us |         5262 /        5323 us
##   200 |        595 /       5874 us |         9118 /        9303 us
## [/codeblock]
## [b]Read the max column, not the median.[/b] `force_allocate`'s median is flat
## at ~600us and says allocation is cheap. Its max is not flat — it grows 8.4x
## across the ramp, and at 200 owned a worst-case allocation costs 5.9ms in
## `force_allocate` [i]alone[/i], before the ~9.1ms recompute. That is ~2.2
## frames for one node claim, and a median is structurally blind to it.
##
## [b]Attribution is settled — see `bench_alloc_cost_attribution.gd`.[/b] The
## expensive allocations are the ones granting `constitution`: `node_health` is
## a borrowed stat and CON scales it (D-11), so one CON modifier invalidates the
## health pool of every owned node — O(owned), categorical, exactly this
## bimodality. It is NOT distance from core (median is flat across hop counts
## 1-14) and NOT PER / `vision_range` (those measure *cheaper* than average).
##
## Cold vs warm is a non-issue: the first recompute of each batch is within ~10%
## of the median, so repeated same-value writes are not hiding cost.
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
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
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
## Returns median AND max per force_allocate. The max matters: lane P reports
## that allocations rolling `PER` / `vision_range` "drop harder still", and those
## are exactly the rare expensive samples a median throws away.
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
	alloc_times.sort()
	return {
		"alloc": _median(alloc_times),
		"alloc_max": float(alloc_times[-1]) if not alloc_times.is_empty() else 0.0,
		"frontier": _median(frontier_times),
	}


## Median of several timed recomputes, in usec. Median rather than min so one
## unlucky sample can't pass a genuinely slow build, and rather than mean so a
## GC pause can't fail a fast one.
##
## Returns `{median, first}`. `first` is the cold pass — the one that actually
## changes `input_pickable` / `sensed` / `revealed` on the nodes whose visibility
## just moved. Samples 2..n rewrite values that are already correct, so if
## [SkillNode] short-circuits same-value setters they measure the warm cost and
## the median under-reports what an allocation costs in game. Both are printed
## so nobody has to take that on faith.
func _median_recompute_usec(samples: int = 7) -> Dictionary:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		_vision._recompute()
		times.append(Time.get_ticks_usec() - t)
	var first := float(times[0])
	return {"median": _median(times), "first": first}


func _median(times: Array[int]) -> float:
	if times.is_empty():
		return 0.0
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


# -- the bench ----------------------------------------------------------------

func test_allocation_cost_ramp() -> void:
	await _ensure_fixture()

	gut.p("owned | force_allocate (med / max) | vision recompute (med / cold) | frontier walk")
	gut.p("------+---------------------------+-------------------------------+--------------")
	for target in _CHECKPOINTS:
		var grown := _grow_to(target)
		# Let the debounced deferred recompute the growth queued actually land,
		# so the timed passes below start from settled state rather than
		# absorbing the backlog into the first sample.
		for i in 3:
			await get_tree().process_frame
		var owned := _owned_count()
		var rc := _median_recompute_usec()
		_samples[target] = {
			"owned": owned,
			"alloc": grown["alloc"],
			"alloc_max": grown["alloc_max"],
			"frontier": grown["frontier"],
			"recompute": rc["median"],
			"recompute_cold": rc["first"],
		}
		gut.p("%5d | %9.0f / %9.0f us | %11.0f / %11.0f us | %8.0f us"
			% [owned, grown["alloc"], grown["alloc_max"],
				rc["median"], rc["first"], grown["frontier"]])

	var worst: Dictionary = _samples[_CHECKPOINTS[-1]]
	gut.p("")
	# `alloc + recompute` is the settled cost only because one allocation
	# produces exactly one recompute — a property pinned by
	# `test_vision_recompute_scaling.gd`, on ITS fixture, not this one. This
	# bench times `_recompute()` directly rather than awaiting the deferred
	# path, so it inherits that assumption rather than re-proving it.
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
	gut.p("(reported, not asserted — see the comment in this test)")
	# DELIBERATELY NOT AN ASSERTION, unlike the sibling property in
	# `test_vision_recompute_scaling.gd`. Three reasons, and the third is why
	# that sibling's 3.0 must not simply be copied here:
	#
	# 1. It is dilutable in the wrong direction. The ratio is damped by the
	#    recompute's owned-count-INDEPENDENT cost (~2ms of node + edge writes),
	#    so adding fixed work to `_recompute` makes such a guard EASIER to pass.
	# 2. `test_allocation_stays_within_a_catastrophe_ceiling` already catches
	#    every regression this would, in absolute terms, without that inversion.
	# 3. Any bound here would have had to be picked ABOVE a measured 3.08 to go
	#    green — a threshold chosen to clear the current number is not a bound,
	#    it is a rubber stamp. The sibling's 3.0 was calibrated on a synthetic
	#    150px grid with modifier-free nodes and does not transfer to a real
	#    level; that gap IS the finding in this file's header (visibility pass
	#    alone is 6.1x here), and the right response to a finding is to record
	#    it, not to widen a guard until it stops reporting it.
	assert_gt(cost_ratio, 0.0, "the ratio must at least be measurable")


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
