extends GutTest

## [b]#470 investigation[/b] — is the CON allocation cost a linear fan-out, and
## where inside it do the ~30us/node actually go?
##
## Companion to `bench_alloc_cost_attribution.gd`, which established WHICH
## allocations are expensive (the CON-granting ones) but not that the
## `node_health` fan-out is the [i]cause[/i], and not what the per-node cost is
## made of. Three probes here:
##
## 1. [b]Ablation.[/b] Re-run the same ramp with the entity `node_health` ->
##    per-node listeners severed before each timed allocation. It was the
##    ablation that proved the fan-out causal; post-#660 there are no per-node
##    listeners left to sever, so LIVE and ABLATED converging IS the fix.
## 2. [b]Within-run regression.[/b] Bucket the CON-granting allocations by
##    `owned_before` and report usec/owned. Flat -> linear; rising -> quadratic.
##    A max at 200 vs a max at 300 is one noisy order statistic; this is not.
## 3. [b]Baseline move (rewritten by #660).[/b] At a fully built territory,
##    time one entity `node_health` move and price the derived reads that
##    replaced the eager push. Acceptance 1 lives here.
##
## [b]Findings 1-7 below are the 2026-08 RECORD of the eager fan-out, kept as
## history — #660 deleted the mechanism they anatomise[/b] (`set_base_ratcheted`
## and `heal_on_max_increase` are both gone; the per-node push is gone). Probes 1
## and 2 still run unchanged and are the before/after; probe 3 was rewritten.
##
## Run: [code]mise run test:one -- res://test/perf/bench_con_fanout.gd[/code]
## `test/perf/` is outside `.gutconfig` and the `bench_` prefix keeps GUT's
## `test_*.gd` collection from finding it.
##
## [b]Blind spot, deliberately not fixed:[/b] no `HudRoot` is attached, so the
## per-node listeners a real level carries are not paid for here (the node pool
## carries exactly 1 `value_changed` listener in this harness). Every number
## below is a floor for in-game cost, not the in-game cost. A `VisionSystem` IS
## attached, matching the sibling bench — measured to make no difference, which
## is itself a result: vision is not on this path.
##
## [b]Findings, 2026-08-24[/b] (RX 7900 XTX, 2000-node `first_level`, 300 owned;
## every figure reproduced within 2% across three runs):
##
## 1. [b]The fan-out is causal, not correlated.[/b] Severing the binding drops
##    CON-granting allocations from mean 1889us / max 3385us to mean 691us /
##    max 873us — statistically indistinguishable from the non-CON population
##    (mean 653us / max 1129us). Nothing else about a CON node is expensive.
## 2. [b]Linear, not quadratic.[/b] Subtracting the ablated baseline per bucket,
##    the fan-out costs a flat [b]~8.2us per owned node[/b] from owned=75 out to
##    owned=300 (14.2 / 8.1 / 8.2 / 8.6 / 8.2 / 8.1 across the buckets; the
##    first is n=16 at low owned, where fixed cost dominates). So 300 owned is
##    ~3.0ms, not the ~13ms a quadratic would predict. This independently
##    agrees with the 8.5us/node the decomposition measures directly.
## 3. [b]Signal dispatch is NOT the overhead.[/b] The entity-side write with no
##    listeners costs 1us; `(a) - (b) - (c)` leaves 13-37us out of ~1700. The
##    cost is entirely inside the per-node callback body.
## 4. [b]The entity/node bin weave is not on this path at all.[/b]
##    `SkillNode.get_local_value` / `ModifierBins.compute`-over-two-sources
##    never runs here; each `Stat.get_value()` folds only its own bins — and
##    still costs ~1.2us for ~5 flops, partly because it allocates a fresh
##    `Array[ModifierBins]` literal (`[bins]`) on every call.
## 5. [b]About a third of the cost is a state mutation, not a recompute.[/b]
##    `node_combat_health` opts into `heal_on_max_increase`, so every cap rise
##    runs `on_max_increased` -> `set_current` (~3.0us/node). That is required
##    D-31 behaviour, and a read-side cache cannot defer it without changing
##    when `current` moves. Per-node accounting of the 8.5us:
##
##      entity node_health.get_value()   ~1.2us  14%   identical for all N
##      _ensure_local_stat                0.8us  10%
##      2x node pool get_value()         ~2.4us  28%   inside set_base_ratcheted
##      base_value write + emit           0.3us   4%
##      on_max_increased -> set_current  ~3.0us  35%   irreducible while eager
##      call/branch overhead             ~0.8us   9%
##
## 6. [b]The issue's headline 5.9ms is stale.[/b] It was measured 2026-08-17;
##    `board.begin_batch()` in `apply_entity_modifiers_to` landed 2026-08-18
##    (414b1e8), turning a node that grants both `constitution` and
##    `node_health` from two full fan-outs into one. Same seed, same graph,
##    same policy RNG — halving 5.9ms lands on the ~3.0ms measured here. The
##    current worst case really is ~3.0ms at 300 owned.
## 7. [b]One of the two reads inside `set_base_ratcheted` is a compulsory
##    miss[/b] — `old_max` straddles the `base_value` write that invalidates
##    it, so no dirty-flag memo can serve it. What IS removable is the call
##    cost: `get_value()` is 1.17us, 0.68us with the per-call
##    `Array[ModifierBins]` literal hoisted, 0.21us fully inlined. So the
##    read-side ceiling is ~37% (memo alone, ~1.6x) to ~49% (memo plus a
##    cheaper read, ~2x) — NOT the 60x the earlier comment hoped for. Getting
##    past 2x means making the fan-out lazy, which means confronting item 5.
## 8. [b]Item 5 overstated the irreducible part.[/b] `heal_on_max_increase` is
##    literally `stat.set_current(stat.current + delta)` — one addition. It
##    measures 3.0us because `set_current` costs 2.3us: 1.18us of that is a
##    `get_value()` re-deriving the cap through the whole modifier pipeline,
##    0.68us is `_coerce` + `current_changed` + `value_changed`, the rest glue.
##    The fill branch IS taken every time (a full-hp node's cap rises and
##    `current` lands exactly on it) and measures FREE — `on_pool_filled` is a
##    no-op virtual and `replenished` has no listener in this harness.
##
##    So one `_sync_combat_health_base` runs FOUR full pipeline evaluations:
##    the entity read, `old_max`, `new_max`, and `set_current`'s own clamp
##    bound — and the fourth recomputes exactly what the third just produced
##    two stack frames up. Two of the four are pure waste (hoist the entity
##    read; pass the known cap down into `set_current`), which is ~28% of the
##    8.4us at zero semantic risk. Only ~1.5us/node is genuinely a mutation.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _CORE_CLASS := preload("res://entity/core/balanced_core.tres")
const _POLICY := preload("res://procgen/placement/greedy_bfs_ball.tres")

const _NODE_COUNT := 2000
const _SEED := 0x57A17EE

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _core: SkillNode


func test_con_fanout() -> void:
	# --- Probe 1 + 2: the ramp, live and ablated, out to 300 owned ----------
	var live := await _ramp(300, false)
	_report_ramp("LIVE (unmodified)", live)
	var ablated := await _ramp(300, true)
	_report_ramp("ABLATED (node_health fan-out severed)", ablated)

	# --- Probe 3: decompose one fan-out at a built territory ----------------
	await _decompose(200)

	assert_gt(live.size(), 0, "probe must have measured something")


## Build a territory to [param target] owned nodes, timing every
## `force_allocate`. With [param ablate], every existing owned node is
## disconnected from the owner's `node_health` stat immediately before each
## timed call, so the allocation pays for its own binding and nothing else.
## Returns rows of `[owned_before, usec, grants_con, stat_ids]`.
func _ramp(target: int, ablate: bool) -> Array:
	await _build_world()
	var policy: AllocationPolicy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	policy.rng = rng

	var rows: Array = []
	while _owned() < target:
		var frontier := _frontier()
		if frontier.is_empty():
			break
		var pick: SkillNode = policy.pick_next(_entity, frontier, null)
		if pick == null:
			break
		var owned_before := _owned()
		var ids: Array[String] = []
		for m in StatModifier.flatten_all(pick.modifiers):
			ids.append(str(m.stat_id))
		var joined := ", ".join(ids)
		var grants_con := joined.contains("constitution") or joined.contains("node_health")
		if ablate:
			_sever_fanout()
		var t := Time.get_ticks_usec()
		_alloc.force_allocate(_entity, pick)
		var usec := Time.get_ticks_usec() - t
		rows.append([owned_before, usec, grants_con, joined])
	return rows


func _report_ramp(label: String, rows: Array) -> void:
	var con_rows: Array = []
	var plain_rows: Array = []
	for r in rows:
		if r[2]:
			con_rows.append(r)
		else:
			plain_rows.append(r)
	gut.p("")
	gut.p("=== %s — n=%d ===" % [label, rows.size()])
	gut.p("  CON-granting : n=%3d  mean=%6.0fus  max=%6dus" % [
		con_rows.size(), _mean(con_rows, 1), _max(con_rows, 1)])
	gut.p("  everything else: n=%3d  mean=%6.0fus  max=%6dus" % [
		plain_rows.size(), _mean(plain_rows, 1), _max(plain_rows, 1)])

	# The linear-vs-quadratic discriminator: usec/owned across the ramp.
	gut.p("  CON-granting allocations bucketed by owned count:")
	gut.p("    owned    | n  | mean us | us per owned node")
	gut.p("    ---------+----+---------+------------------")
	for lo in [0, 50, 100, 150, 200, 250]:
		var bucket: Array = []
		for r in con_rows:
			if r[0] >= lo and r[0] < lo + 50:
				bucket.append(r)
		if bucket.is_empty():
			continue
		var mean_us := _mean(bucket, 1)
		var mean_owned := _mean(bucket, 0)
		gut.p("    %3d-%3d  | %2d | %7.0f | %.2f" % [
			lo, lo + 49, bucket.size(), mean_us,
			mean_us / maxf(mean_owned, 1.0)])


## [b]Probe 3, rewritten by #660.[/b] The old body dissected the per-node
## `_sync_combat_health_base` callback — signal dispatch vs `_ensure_local_stat`
## vs the two pipeline reads. There is no such callback any more: the cap is
## DERIVED on read from the owner's baseline, and the node pool stores damage
## taken, so a `node_health` move does no per-node work at all.
##
## What replaces it is the acceptance criterion itself: time one entity
## baseline move at a fully built territory and show it does not scale with
## owned count, then price the derived READ that pays for it.
func _decompose(target: int) -> void:
	await _build_world()
	var policy: AllocationPolicy = _POLICY.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED ^ 0x8EEDED
	policy.rng = rng
	while _owned() < target:
		var frontier := _frontier()
		if frontier.is_empty():
			break
		var pick: SkillNode = policy.pick_next(_entity, frontier, null)
		if pick == null:
			break
		_alloc.force_allocate(_entity, pick)

	var owned: Array = _entity.navigator.get_mirrored_nodes()
	var nh: Stat = _entity.stat_board.get_stat(&"node_health")
	gut.p("")
	gut.p("=== BASELINE MOVE at %d owned nodes (post-#660) ===" % owned.size())
	if nh == null:
		gut.p("  entity carries no node_health stat — nothing to measure")
		return

	var per := func(us: int) -> float: return float(us) / maxf(owned.size(), 1.0)

	# (a) The whole thing. Under the old push this was O(owned) full pipeline
	#     evaluations; it is now one entity-side stat write plus one re-emit.
	var t := Time.get_ticks_usec()
	nh.base_value += 1.0
	var full := Time.get_ticks_usec() - t

	# (b) The same write with every listener severed — the floor.
	_sever_fanout()
	t = Time.get_ticks_usec()
	nh.base_value += 1.0
	var bare := Time.get_ticks_usec() - t

	# (c) What the laziness costs on the other side: one derived cap read per
	#     owned node. This is the work that USED to be eager and is now paid
	#     only by whoever actually looks — O(visible), not O(owned).
	var pools: Array = []
	for n in owned:
		var pool: Variant = n.node_board.get_stat(&"node_health") if n.node_board != null else null
		if pool != null:
			pools.append(pool)
	t = Time.get_ticks_usec()
	for pool in pools:
		@warning_ignore("unused_variable")
		var v: float = float(pool.value)
	var reads := Time.get_ticks_usec() - t

	# (d) …and the derived `current` on top of it, which is the number a bar draws.
	t = Time.get_ticks_usec()
	for pool in pools:
		@warning_ignore("unused_variable")
		var c: float = float(pool.current)
	var currents := Time.get_ticks_usec() - t

	gut.p("  (a) baseline move, live listeners : %6dus  (%.2fus/owned)" % [full, per.call(full)])
	gut.p("  (b) baseline move, no listeners   : %6dus" % bare)
	gut.p("  (c) derived cap read, %3d pools    : %6dus  (%.2fus/pool)" % [pools.size(), reads, float(reads) / maxf(pools.size(), 1.0)])
	gut.p("  (d) derived current, %3d pools     : %6dus  (%.2fus/pool)" % [pools.size(), currents, float(currents) / maxf(pools.size(), 1.0)])
	gut.p("  ACCEPTANCE 1: (a) must not scale with owned count — compare against")
	gut.p("  the bucketed us-per-owned table above, which must now be flat.")

func _sever_fanout() -> void:
	var nh: Stat = _entity.stat_board.get_stat(&"node_health")
	if nh == null:
		return
	for c in nh.value_changed.get_connections():
		nh.value_changed.disconnect(c["callable"])


func _build_world() -> void:
	_teardown()
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
	cfg.seed = _SEED

	_graph = _GRAPH_SCENE.instantiate()
	add_child(_graph)
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_false(starting_nodes.is_empty())

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

	# Present so this harness matches `bench_alloc_cost_attribution.gd`'s —
	# otherwise the absolute usec are not comparable to the 5.9ms this issue
	# was filed on.
	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.allocation_system = _alloc
	_vision.viewers = [_entity]
	add_child(_vision)
	await get_tree().process_frame


func _teardown() -> void:
	for n in [_vision, _alloc, _graph]:
		if is_instance_valid(n):
			n.free()
	_vision = null
	_alloc = null
	_graph = null
	_entity = null
	_core = null


func _mean(rs: Array, col: int) -> float:
	if rs.is_empty():
		return 0.0
	var s := 0.0
	for r in rs:
		s += float(r[col])
	return s / float(rs.size())


func _max(rs: Array, col: int) -> int:
	var m := 0
	for r in rs:
		m = maxi(m, int(r[col]))
	return m


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
	_teardown()
