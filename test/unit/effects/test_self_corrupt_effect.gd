extends GutTest

## `abyssal_conduit_addon.tscn` + [SelfCorruptEffect] — Corruption × Addon's
## bargain. Held, the gate grants its owner +3 `corruption_aspect`, and at
## each of the owner's turn starts it grows `stacks_per_turn` corruption on
## its own node. Cutting the node stops the growth and takes the grant; an
## enemy's turn start adds nothing.
##
## Fixture: the owner's core and the gate node, one edge; an enemy on a camp
## of its own. The addon is attached BEFORE allocation, so the real grant path
## ([method AllocationSystem.force_allocate] → node effects) carries it.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _GATE_SCENE := preload("res://skill_node/addons/defs/abyssal_conduit_addon.tscn")
const _CORRUPTION := preload("res://effects/status/corruption.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _owner: Entity
var _enemy: Entity
var _core: SkillNode
var _gate_node: SkillNode
var _gate: SkillNodeAddon
var _aspect_base: float


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _make_entity() -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	_graph.add_child(entity)
	return entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_owner = _make_entity()
	_enemy = _make_entity()
	var enemy_camp := Faction.new()
	enemy_camp.id = &"gate_enemy"
	_enemy.faction = enemy_camp

	_core = _spawn("Core", Vector2.ZERO)
	_gate_node = _spawn("Gate", Vector2(150.0, 0.0))
	_graph.add_edge(_core, _gate_node)
	var camp := _spawn("Camp", Vector2(-600.0, 600.0))
	_gate = _GATE_SCENE.instantiate() as SkillNodeAddon
	_gate_node.add_child(_gate)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_owner, _core)
	_owner.core_location = _core
	_alloc.force_allocate(_enemy, camp)
	_enemy.core_location = camp
	_aspect_base = _aspect()
	_alloc.force_allocate(_owner, _gate_node)


func _aspect() -> float:
	return float(_owner.stat_board.get_value(&"corruption_aspect"))


func _row() -> float:
	return _gate_node.get_combat().get_status_power(_CORRUPTION.id)


func _per_turn() -> int:
	for e in _gate.effects:
		if e is SelfCorruptEffect:
			return (e as SelfCorruptEffect).stacks_per_turn
	assert_true(false, "the gate carries a SelfCorruptEffect")
	return -1


func test_holding_the_gate_grants_three_corruption_aspect() -> void:
	assert_eq(_aspect() - _aspect_base, 3.0)


func test_each_owner_turn_start_grows_the_row_on_the_gate_node() -> void:
	assert_eq(_row(), 0.0, "nothing before the first turn")
	_owner.dispatch(&"_on_turn_start")
	assert_eq(_row(), float(_per_turn()), "one turn: stacks_per_turn")
	_owner.dispatch(&"_on_turn_start")
	assert_eq(_row(), 2.0 * _per_turn(), "two turns: twice")


func test_the_gate_grows_only_its_own_node() -> void:
	_owner.dispatch(&"_on_turn_start")
	assert_eq(_core.get_combat().get_status_power(_CORRUPTION.id), 0.0)


func test_an_enemy_turn_start_adds_nothing() -> void:
	_enemy.dispatch(&"_on_turn_start")
	assert_eq(_row(), 0.0)


func test_cutting_the_gate_stops_the_growth_and_takes_the_grant() -> void:
	_owner.dispatch(&"_on_turn_start")
	_alloc.force_deallocate(_gate_node)
	assert_eq(_aspect(), _aspect_base, "the +3 goes with the node")
	var after_cut := _row()
	_owner.dispatch(&"_on_turn_start")
	assert_eq(_row(), after_cut, "no growth while the gate is cut")


func test_reallocating_resumes_from_the_row_that_is_there() -> void:
	_owner.dispatch(&"_on_turn_start")
	_alloc.force_deallocate(_gate_node)
	# Corruption's `on_dealloc` decides what survives the cut; the gate resumes
	# from whatever row is left, never from a remembered count.
	var left := _row()
	_alloc.force_allocate(_owner, _gate_node)
	assert_eq(_aspect() - _aspect_base, 3.0, "the grant returns")
	_owner.dispatch(&"_on_turn_start")
	assert_eq(_row(), left + _per_turn())
