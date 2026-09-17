extends GutTest

## #942: what [method NodeTargeting.valid_targets] costs on a real board, at the
## scale the owner is aiming for ("2k definitely, 3k stretch").
##
## Run: [code]mise run test:one -- res://test/perf/bench_targeting_valid_targets.gd[/code]
##
## [b]Not collected by the suite[/b] — same double opt-out as its siblings:
## `test/perf/` is outside `.gutconfig.json`'s `test/unit/`, and `bench_` keeps
## even `test:dir` from finding it.
##
## Two implementations of the same set are timed side by side on the SAME
## fixture, and that is the assertion:
##
## - [method Targeting._filter_skill_nodes] — the pre-#942 default, still the
##   base path for targetings with no range finder: every board node through
##   [method NodeTargeting.is_valid_target], which for a hop finder is one
##   `AStar2D.get_id_path` per candidate. N nodes = N path searches.
## - [method NodeTargeting.valid_targets] — one [method RangeFinder.gather]
##   sweep (a hop-bounded BFS) then the ownership filter.
##
## The bench asserts the sweep lands an order of magnitude under the per-pair
## walk [i]as measured in the same run[/i], not under a pinned number: the
## dev box's absolute time is reported, never asserted, so a slower or busier
## machine does not turn a perf property into a flaky test. The two sets are
## also asserted equal on this real board — the unit-test equivalence, once
## more, at scale.
##
## Numbers move with the machine — record the CPU and load alongside any result.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")

## North Star (docs/FOCUS.md): a 2000-node map at 144Hz. One frame's budget.
const _FRAME_BUDGET_USEC := 6944.0
const _NODE_COUNT := 2000
## Pinned so content — and therefore cost — is comparable across commits.
const _SEED := 0x57A17EE
const _MAX_HOPS := 3
const _SAMPLES := 7

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _source: SkillNode
var _built := false


func _ensure_fixture() -> void:
	if _built:
		return
	_built = true

	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	# #349: topology is a top-level module .tres; duplicate(true) does not cross
	# that boundary, so re-duplicate before mutating.
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
	cfg.seed = _SEED
	# One camp of one: a single caster core and no AI starters, so the board
	# is neutral except the source and the sweep's reach is pure topology.
	cfg.camp_sizes = [1]

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

	# entity.tscn, not Entity.new(): _ready duplicates the stat board and builds
	# the EntityNavigator; attacker.navigator.graph is what targeting reads.
	_entity = _ENTITY_SCENE.instantiate() as Entity
	_entity.name = "BenchCaster"
	_entity.display_name = "BenchCaster"
	_entity.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame

	_source = starting_nodes[0]
	_alloc.force_allocate(_entity, _source)
	_entity.core_location = _source
	await get_tree().process_frame

	gut.p("--- fixture: %s, node_count=%d, seed=0x%X, generated in %d ms, max_hops=%d ---"
		% [_PRESET.resource_path.get_file(), _graph.get_skill_nodes().size(), _SEED, gen_ms, _MAX_HOPS])


func after_all() -> void:
	# free(), not queue_free(): GUT's unfreed-children check runs before the
	# deferred queue drains. Alloc first — it holds references into the graph.
	for n in [_alloc, _graph]:
		if is_instance_valid(n):
			n.free()


func _targeting() -> NodeTargeting:
	var finder := HopRangeFinder.new()
	finder.max_hops = _MAX_HOPS
	var t := NodeTargeting.new()
	t.ownership_filter = 15  # Any: the sweep's cost, not the filter's selectivity
	t.range_finder = finder
	return t


func _plan() -> AttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _entity
	return plan


## Median of [param samples] timed calls, in usec. Median rather than min so
## one lucky sample can't pass a slow build, and rather than mean so a GC pause
## can't fail a fast one.
func _median_usec(fn: Callable, samples: int = _SAMPLES) -> float:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		fn.call()
		times.append(Time.get_ticks_usec() - t)
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


func _names(nodes: Array) -> Array[String]:
	var out: Array[String] = []
	for n in nodes:
		out.append(String(n.name))
	out.sort()
	return out


func test_sweep_is_an_order_of_magnitude_under_the_per_pair_walk() -> void:
	await _ensure_fixture()
	if _source == null:
		return
	var t := _targeting()
	var plan := _plan()

	var per_pair_set := _names(t._filter_skill_nodes(plan, _source))
	var sweep_set := _names(t.valid_targets(plan, _source))
	assert_eq(sweep_set, per_pair_set,
		"the sweep must reproduce the per-pair set on a real board")
	assert_gt(sweep_set.size(), 1, "the source must reach something in %d hops" % _MAX_HOPS)

	var per_pair_usec := _median_usec(func() -> void: t._filter_skill_nodes(plan, _source))
	var sweep_usec := _median_usec(func() -> void: t.valid_targets(plan, _source))

	gut.p("nodes | per-pair walk (median) | gather sweep (median) | speedup | reach")
	gut.p("------+------------------------+-----------------------+---------+------")
	gut.p("%5d | %19.0f us | %18.0f us | %6.1fx | %d nodes"
		% [_graph.get_skill_nodes().size(), per_pair_usec, sweep_usec,
			per_pair_usec / maxf(sweep_usec, 1.0), sweep_set.size()])
	gut.p("sweep = %.2f frames of the %.0f us 144Hz budget"
		% [sweep_usec / _FRAME_BUDGET_USEC, _FRAME_BUDGET_USEC])
	if sweep_usec > 2000.0:
		gut.p("(reported, not asserted: the #942 target is <2 ms on the dev box)")

	assert_lt(sweep_usec * 10.0, per_pair_usec,
		"one gather sweep (%.0f us) must land an order of magnitude under the per-pair AStar walk (%.0f us)"
			% [sweep_usec, per_pair_usec])
