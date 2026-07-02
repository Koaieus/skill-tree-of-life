extends GutTest

## SkillNode combat-HP invariant across allocation cycles (related: #92).
##
## Invariant under test: an allocated node is always at full `current_hp`, and a
## deallocated node has none — held across repeated allocate/deallocate cycles.
##
## NOTE on #92 ("health stuck at 0/N"): the root cause was owner_changed handler
## ordering — `_refresh_hp_binding` (refill → get_max_hp → reads the cached
## `node_health` LocalStat) ran BEFORE `_refresh_local_stat_bindings` rebound that
## LocalStat to the new owner, so a re-allocation refilled against a LocalStat
## still unbound from the prior dealloc. The fix (rebind-before-refill) is in
## skill_node.gd. These tests DON'T reproduce the exact 0/N symptom: it only
## surfaces when the LocalStat is materialized *before* dealloc (in-game, the
## HealthBar's deferred _sync calls get_max_hp on the unowned node); this headless
## fixture creates it fresh mid-refill, which masks the bug. They stand as
## positive-invariant coverage — the 0/N repro needs in-game HealthBar timing.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Cycler"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_entity)

	await get_tree().process_frame  # entity._ready


func test_current_hp_full_on_first_allocation() -> void:
	_alloc.force_allocate(_entity, _node)
	var maxv := _node.get_max_hp()
	assert_gt(maxv, 0.0, "node_health max should be positive when owned")
	assert_almost_eq(_node.current_hp, maxv, 0.001,
			"freshly allocated node should be at full HP")


func test_current_hp_refills_after_realloc_cycle() -> void:
	# Cycle allocate → deallocate → allocate. The second allocation is where the
	# stale-LocalStat bug struck.
	_alloc.force_allocate(_entity, _node)
	_alloc.force_deallocate(_node)
	assert_eq(_node.owned_by, null, "node should be unowned after dealloc")
	assert_almost_eq(_node.current_hp, 0.0, 0.001, "unowned node has no HP")

	_alloc.force_allocate(_entity, _node)
	var maxv := _node.get_max_hp()
	assert_gt(maxv, 0.0, "re-allocated node_health max should be positive")
	assert_almost_eq(_node.current_hp, maxv, 0.001,
			"re-allocated node must refill to full — not stay stuck at 0/N (#92)")


func test_realloc_reads_modified_max_not_stale_default() -> void:
	# The actual #92 reproduction. A +40 node_health modifier makes the entity's
	# real max 50, while node_health's default_value is 10. If the HP refill on
	# re-allocation reads a LocalStat still unbound from the prior dealloc, it
	# sees the stale default (10) or 0 instead of 50 — the "0/N"-class bug. With
	# the rebind-before-refill ordering it reads the true 50.
	var nh := _entity.stat_board.get_stat(&"node_health")
	var m := StatModifier.new()
	m.stat_id = &"node_health"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 40.0
	nh.add_modifier(m)

	_alloc.force_allocate(_entity, _node)
	assert_almost_eq(_node.get_max_hp(), 50.0, 0.001, "modified max should be 50")
	_alloc.force_deallocate(_node)
	_alloc.force_allocate(_entity, _node)

	assert_almost_eq(_node.current_hp, 50.0, 0.001,
			"re-alloc must refill to the MODIFIED max (50), not a stale default/0 (#92)")


func test_multiple_cycles_stay_full() -> void:
	# Several cycles — the cache-driven "sometimes" nature means we exercise more
	# than one round-trip.
	for i in 4:
		_alloc.force_allocate(_entity, _node)
		var maxv := _node.get_max_hp()
		assert_almost_eq(_node.current_hp, maxv, 0.001,
				"cycle %d: node should be full after allocate" % i)
		_alloc.force_deallocate(_node)
