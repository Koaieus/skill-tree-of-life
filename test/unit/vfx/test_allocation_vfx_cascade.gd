extends GutTest

## #870 — the Allocation VFX sandbox's bottom row drives the cascade through a
## bare LIVE-world `SkillNode.take_damage(99999.0, null)` (no `HitInstance`,
## no `AttackRecord`): `BattleSystem._on_node_depleted`'s **derive** branch
## (a non-empty `recorded` never populates, so it walks `cascade_set` itself)
## announces `cascade_started`, and `AllocationVFX._on_cascade_started` /
## `_on_force_deallocated` are what turn that into shatters.
##
## This pins the CPU-side contract end-to-end — signal fires, snapshot
## carries the right ripple delay per BFS layer, shards land in the pool —
## the actual pixels still want a `mise run play` look per the issue.


var _w: TestWorld
var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _vfx: AllocationVFX
var _entity: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_w = TestWorld.create(self)
	_graph = _w.graph

	_nodes = []
	for i in 3:
		_nodes.append(_w.add_node(StringName("N%d" % i)))
	# Line core(N0) - N1 - N2. N1 is a cut vertex: depleting it islands N2 too
	# -> a 2-layer cascade ([N1], [N2]), same topology as the sandbox's
	# `cascade_mid` cell (#870).
	_w.link(_nodes[0], _nodes[1])
	_w.link(_nodes[1], _nodes[2])

	_alloc = _w.allocator()

	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	_vfx = AllocationVFX.new()
	_vfx.shatter_shard_count = 4
	_graph.add_child(_vfx)
	autofree(_vfx)
	_vfx.bind(_alloc, _battle)

	_entity = _w.add_entity("Victim")

	await get_tree().process_frame  # entity._ready: navigator wiring

	for n in _nodes:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _nodes[0]
	_entity.stat_board.health.base_value = 100.0
	_entity.stat_board.health.set_current(100.0)


## The regression this issue describes: a record-less depletion
## (`take_damage(_, null)`) on the live world must still reach
## `BattleSystem.cascade_started` with both cascaded nodes, one layer each.
func test_liveworld_recordless_depletion_emits_cascade_started() -> void:
	# A GDScript lambda captures outer locals by value on read but never
	# writes back on reassignment — so the sink is a mutable Array
	# (`append`, never `=`) the same way the loot/victory-system tests do it.
	var seen: Array = []
	var handler := func(layers: Array, defender: Entity) -> void:
		seen.append([layers, defender])
	_battle.cascade_started.connect(handler)

	_nodes[1].take_damage(10000.0, null)

	assert_eq(seen.size(), 1, "cascade_started should fire exactly once")
	var layers: Array = seen[0][0]
	var defender: Entity = seen[0][1]
	assert_eq(defender, _entity)
	assert_eq(layers.size(), 2, "N1 (impact) then N2 (islanded) as separate ripple layers")
	assert_eq((layers[0] as Array), [_nodes[1]])
	assert_eq((layers[1] as Array), [_nodes[2]])


## The other half: AllocationVFX actually turns that signal into shards —
## one `shatter_shard_count`-sized burst per cascaded node, staggered by
## `CASCADE_STEP` per BFS layer (0.0 for the impact, `CASCADE_STEP` for the
## islanded ring behind it).
func test_liveworld_recordless_depletion_spawns_staggered_shatters() -> void:
	var field := _vfx.get_shard_field()
	var before := field.used_slots()
	# `_spawn_shatter` stamps `elapsed + delay`, and `_vfx._process` may have
	# already ticked `elapsed` off a real frame delta during `before_each`'s
	# `await process_frame` — baseline it rather than assume 0.0.
	var baseline: float = field.elapsed

	_nodes[1].take_damage(10000.0, null)

	var after := field.used_slots()
	assert_eq(after - before, _vfx.shatter_shard_count * 2,
			"one shard burst per cascaded node (N1 + N2)")
	# First burst (N1, impact) delay 0.0, second burst (N2, islanded) delay
	# CASCADE_STEP — the ripple AllocationVFX._on_cascade_started stages off
	# BFS layer index.
	for slot in range(before, before + _vfx.shatter_shard_count):
		assert_almost_eq(field.shard_spawn_time(slot), baseline, 0.0001)
	for slot in range(before + _vfx.shatter_shard_count, after):
		assert_almost_eq(field.shard_spawn_time(slot), baseline + _vfx.CASCADE_STEP, 0.0001)
