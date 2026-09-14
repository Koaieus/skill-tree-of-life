extends GutTest

## #879 — the lifecycle wiring around NodeCombat's status slice (#872):
## - the sparse `Events.turn_started` tick subscription, entity-filtered and
##   never firing on a resync `adopt_turn`;
## - tick running strictly AFTER `Entity._on_turn_started`'s own upkeep
##   (regen included), same emit;
## - every `AllocationSystem` dealloc path clearing statuses.
## `test_node_combat_status.gd` pins apply/tick/remove/clear by hand; this
## file is the wiring that calls `tick_statuses()` for real.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


## A StatusDef whose `_on_tick` damages the node — journals ticks so a test
## can count them, and doubles as the "poison"-shaped def the ordering test
## needs (damage -> `_damaged_since_upkeep` -> next turn's regen gate).
class SpyDef:
	extends StatusDef
	var ticks: Array = []
	var damage_per_tick: float = 0.0

	func _on_tick(node: NodeCombat, before: float, after: float) -> void:
		ticks.append([before, after])
		if damage_per_tick > 0.0:
			node.take_damage(damage_per_tick, null)


var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)


func _make_entity(n: String) -> Entity:
	var e := Entity.new()
	e.name = n
	e.display_name = n
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return e


func _def(id: StringName, power_max: float, decay: float = 1.0) -> SpyDef:
	var d := SpyDef.new()
	d.id = id
	d.power_max = power_max
	d.decay_per_tick = decay
	return d


func _new_node() -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(n)
	return n


# ── Sparse subscription: entity-filtered, never on adopt_turn ───────────────

func test_status_ticks_only_on_owning_entitys_real_turn_never_on_adopt() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	var b: Entity = autofree(_make_entity("B"))
	_graph.entities_container.add_child(b)
	await get_tree().process_frame

	var node_a := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node_a)
	a.core_location = node_a

	var d := _def(&"poison", 5.0)
	node_a.get_combat().apply_status(d, 3.0)

	# A resync repair is not a real turn begin.
	_tm.adopt_turn(a, 1)
	assert_eq(d.ticks.size(), 0, "adopt_turn must never tick a status")
	_tm.current_entity = null

	# B's real turn: A's status must not tick.
	_tm.start_turn(b)
	assert_eq(d.ticks.size(), 0, "A's status must not tick on B's turn")
	_tm.current_entity = null  # bypass end_turn's auto-tick-to-ready; not under test here

	# A's real turn: ticks exactly once.
	_tm.start_turn(a)
	assert_eq(d.ticks.size(), 1, "A's own real turn start ticks its status exactly once")


# ── Ordering: tick runs strictly after regen (hub D4) ────────────────────────

func test_tick_runs_after_regen_so_its_own_damage_only_gates_the_next_turn() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var node_a := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node_a)
	a.core_location = node_a

	# Entity._on_turn_started runs no upkeep at all on turns_taken == 1 (you
	# spawn as-is, not one free tick richer) — prime that throwaway first
	# turn before the two turns this test actually measures.
	_tm.start_turn(a)
	_tm.current_entity = null  # bypass end_turn's auto-tick-to-ready

	# Below max HP (regen-eligible) without tripping `_damaged_since_upkeep` —
	# restore_current_hp bypasses damage/heal signals by design.
	node_a.restore_current_hp(maxf(node_a.get_max_hp() - 10.0, 0.0))

	var d := _def(&"poison", 10.0, 1.0)
	d.damage_per_tick = 1.0
	node_a.get_combat().apply_status(d, 5.0)

	# Turn 2 (the first turn regen actually runs on): this turn's regen
	# decision was made BEFORE this turn's own tick ran, so it is not
	# suppressed by damage that tick is about to deal.
	_tm.start_turn(a)
	assert_eq(node_a.regen_stacks, 1,
			"this turn's regen must not be suppressed by this same turn's tick damage")
	_tm.current_entity = null  # bypass end_turn's auto-tick; not under test here

	# Turn 3: the PRIOR turn's tick damage is what the ordering promises to
	# have flagged — this turn's regen must see it and reset to 0.
	_tm.start_turn(a)
	assert_eq(node_a.regen_stacks, 0,
			"this turn's regen must see the PRIOR turn's tick damage and suppress")


# ── Clear on ownership loss ───────────────────────────────────────────────────

func test_force_deallocate_clears_statuses_and_stops_ticking() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core

	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node)

	var d := _def(&"poison", 5.0)
	node.get_combat().apply_status(d, 3.0)
	assert_false(node.get_combat().get_statuses().is_empty())

	_alloc.force_deallocate(node)
	assert_true(node.get_combat().get_statuses().is_empty(),
			"force_deallocate must clear the node's statuses")

	_tm.start_turn(a)
	assert_eq(d.ticks.size(), 0, "a node cleared by force_deallocate must not tick")


func test_deallocate_voluntary_clears_statuses() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core

	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node)

	var d := _def(&"blind", 5.0)
	node.get_combat().apply_status(d, 2.0)

	assert_true(_alloc.deallocate(node, a), "precondition: a plain non-core dealloc must succeed")
	assert_true(node.get_combat().get_statuses().is_empty(),
			"voluntary deallocate must clear statuses")


func test_deallocate_all_owned_clears_every_owned_nodes_statuses() -> void:
	var a: Entity = autofree(_make_entity("A"))
	_graph.entities_container.add_child(a)
	await get_tree().process_frame

	var core := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, core)
	a.core_location = core

	var node := _new_node()
	await get_tree().process_frame
	_alloc.force_allocate(a, node)

	var d_core := _def(&"poison", 5.0)
	var d_node := _def(&"blind", 5.0)
	core.get_combat().apply_status(d_core, 2.0)
	node.get_combat().apply_status(d_node, 2.0)

	_alloc.deallocate_all_owned(a)
	assert_true(core.get_combat().get_statuses().is_empty(), "core's statuses must clear too")
	assert_true(node.get_combat().get_statuses().is_empty())

	_tm.start_turn(a)
	assert_eq(d_core.ticks.size(), 0)
	assert_eq(d_node.ticks.size(), 0)
