extends GutTest

## [b]Which[/b] allocations are expensive, and why. Companion to
## `bench_allocation_cost.gd`, which measures the ramp but cannot attribute it:
## that bench grows a greedy BFS ball, so owned-count and distance-from-core are
## perfectly confounded — every later allocation is both on a bigger territory
## and further out. This one records per-allocation `(owned, hops, usec, stats
## granted)` and splits the factors apart.
##
## Run: [code]mise run test:one -- res://test/perf/bench_alloc_cost_attribution.gd[/code]
## Same exclusion as its sibling: `test/perf/` is outside `.gutconfig`, and the
## `bench_` prefix keeps GUT's `test_*.gd` collection from finding it.
##
## [b]Findings, 2026-08-17[/b] (RX 7900 XTX, 2000-node `first_level`, 200 owned):
##
## 1. [b]Distance from core does not matter.[/b] Median cost is flat at ~610us
##    for every hop count from 1 to 14. Hops correlate with cost only because
##    the BFS ball reaches further out later, when more is owned.
## 2. [b]The distribution is bimodal, not a ramp.[/b] Most allocations cost
##    ~600us; a minority cost 2500-4400us. Owned count sets how expensive the
##    expensive ones are; it does not decide which ones they are.
## 3. [b]`constitution` is what decides.[/b] All 12 of the most expensive
##    allocations grant `constitution` (or its dependent `node_health`); none of
##    the 12 cheapest do — those grant `strength` / `dexterity` /
##    `intelligence` / `crit_multiplier` and sit at a flat ~530us regardless of
##    owned count. The mechanism is documented, not inferred: `node_health` is a
##    [b]borrowed[/b] stat (see `.claude/rules/stats-system.md` — the entity
##    carries the baseline) and CON scales it per D-11, so one CON modifier
##    invalidates the health pool of [i]every owned node[/i]. That is O(owned),
##    categorical, and exactly the shape measured.
## 4. [b]The PER / vision_range hypothesis is dead — inverted, in fact.[/b] Lane
##    P reported "if the rolled modifier includes PER or vision_range it drops
##    harder still". Grouped over 199 allocations: vision-touching mean 611us,
##    everything else mean 964us. Vision modifiers are the CHEAP ones here.
##    Whatever the playtest saw, it is not in `force_allocate` — it is
##    downstream, in the vision recompute or the fog render.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")

const _NODE_COUNT := 2000
const _SEED := 0x57A17EE
const _TARGET := 200

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _core: SkillNode


func test_what_makes_an_allocation_expensive() -> void:
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.node_count = _NODE_COUNT
	cfg.seed = _SEED
	cfg.n_random_starters = 0

	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_false(starting_nodes.is_empty())
	if starting_nodes.is_empty():
		return

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child(_alloc)

	_entity = _ENTITY_SCENE.instantiate() as Entity
	_entity.name = "ProbePlayer"
	_entity.core_class = _CORE_CLASS
	_graph.entities_container.add_child(_entity)
	await get_tree().process_frame

	_core = starting_nodes[0]
	_alloc.force_allocate(_entity, _core)
	_entity.core_location = _core

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.allocation_system = _alloc
	_vision.viewers = [_entity]
	add_child(_vision)
	await get_tree().process_frame

	var policy: AllocationPolicy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	policy.rng = rng

	# (owned_before, hops_from_core, usec, n_modifiers) per allocation.
	var rows: Array = []
	while _owned() < _TARGET:
		var frontier := _frontier()
		if frontier.is_empty():
			break
		var pick: SkillNode = policy.pick_next(_entity, frontier, null)
		if pick == null:
			break
		var owned_before := _owned()
		var leaves := StatModifier.flatten_all(pick.modifiers)
		var n_mods: int = leaves.size()
		var stat_ids: Array[String] = []
		for m in leaves:
			stat_ids.append(str(m.stat_id))
		var n_effects: int = pick.effects.size() if "effects" in pick else -1
		var t := Time.get_ticks_usec()
		_alloc.force_allocate(_entity, pick)
		var usec := Time.get_ticks_usec() - t
		# After the claim, so the node is in the mirror. Outside the timed span.
		var hops: int = maxi(_entity.navigator.path_between(pick, _core).size() - 1, 0)
		rows.append([owned_before, hops, usec, n_mods, ", ".join(stat_ids), n_effects])

	# --- Bucket by hops, ignoring owned count -------------------------------
	var by_hops: Dictionary = {}
	for r in rows:
		var h: int = r[1]
		if not by_hops.has(h):
			by_hops[h] = []
		by_hops[h].append(r[2])
	gut.p("hops | n   | median us | max us")
	gut.p("-----+-----+-----------+--------")
	var hop_keys: Array = by_hops.keys()
	hop_keys.sort()
	for h in hop_keys:
		var v: Array = by_hops[h]
		v.sort()
		@warning_ignore("integer_division")
		gut.p("%4d | %3d | %9d | %6d" % [h, v.size(), v[v.size() / 2], v[-1]])

	# --- The 10 most expensive allocations, with both candidate causes -------
	var sorted_rows := rows.duplicate()
	sorted_rows.sort_custom(func(a, b): return a[2] > b[2])
	gut.p("")
	gut.p("12 most expensive allocations:")
	gut.p("  usec | owned | hops | eff | stats granted")
	for i in mini(12, sorted_rows.size()):
		var r: Array = sorted_rows[i]
		gut.p("%6d | %5d | %4d | %3d | %s" % [r[2], r[0], r[1], r[5], r[4]])
	gut.p("")
	gut.p("12 cheapest allocations (for contrast):")
	gut.p("  usec | owned | hops | eff | stats granted")
	for i in range(maxi(sorted_rows.size() - 12, 0), sorted_rows.size()):
		var r: Array = sorted_rows[i]
		gut.p("%6d | %5d | %4d | %3d | %s" % [r[2], r[0], r[1], r[5], r[4]])

	# --- Does touching a vision-relevant stat explain the split? ------------
	# Lane P's report: "if the rolled modifier includes PER or vision_range it
	# drops harder still". A modifier on those changes the ENTITY stat that
	# every owned node's local vision_range derives from — which would be
	# O(owned) work, categorical, and would show up as exactly this bimodality.
	var vision_rows: Array = []
	var plain_rows: Array = []
	for r in rows:
		var ids: String = r[4]
		if ids.contains("per") or ids.contains("vision") or ids.contains("sensor"):
			vision_rows.append(r)
		else:
			plain_rows.append(r)
	gut.p("")
	gut.p("grouped by whether the node grants a PER / vision / sensor modifier:")
	gut.p("  vision-touching: n=%d  mean usec=%.0f  mean owned=%.0f"
		% [vision_rows.size(), _mean(vision_rows, 2), _mean(vision_rows, 0)])
	gut.p("  everything else: n=%d  mean usec=%.0f  mean owned=%.0f"
		% [plain_rows.size(), _mean(plain_rows, 2), _mean(plain_rows, 0)])

	# --- Correlate cost against each candidate separately -------------------
	gut.p("")
	gut.p("cheapest quartile vs most expensive quartile, by mean of each factor:")
	@warning_ignore("integer_division")
	var q := int(rows.size() / 4)
	var cheap := sorted_rows.slice(sorted_rows.size() - q, sorted_rows.size())
	var dear := sorted_rows.slice(0, q)
	gut.p("  cheap: mean owned=%.0f  mean hops=%.1f  mean mods=%.2f  mean usec=%.0f"
		% [_mean(cheap, 0), _mean(cheap, 1), _mean(cheap, 3), _mean(cheap, 2)])
	gut.p("  dear:  mean owned=%.0f  mean hops=%.1f  mean mods=%.2f  mean usec=%.0f"
		% [_mean(dear, 0), _mean(dear, 1), _mean(dear, 3), _mean(dear, 2)])

	assert_gt(rows.size(), 0, "probe must have measured something")


func _mean(rs: Array, col: int) -> float:
	if rs.is_empty():
		return 0.0
	var s := 0.0
	for r in rs:
		s += float(r[col])
	return s / float(rs.size())


func _owned() -> int:
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


func after_all() -> void:
	for n in [_vision, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()
