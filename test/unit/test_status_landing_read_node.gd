extends GutTest

## Status landing folds `<family>_stacks_per_hit` through the hit's
## [member HitInstance.read_node] — entity bins, then that node's local bins,
## then the authored power as a `base_add` overlay — so a modifier local to the
## attacking node scales only the hits that node reads for, and the slice read
## is the landing world's. No read node falls back to the entity board.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _POISON := preload("res://effects/status/poison.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _blade: SkillNode
var _sibling: SkillNode
var _target: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_attacker = _entity("Attacker")
	_defender = _entity("Defender")
	_blade = _node()
	_sibling = _node()
	_target = _node()
	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _blade)
	_alloc.force_allocate(_attacker, _sibling)
	_attacker.core_location = _blade
	_alloc.force_allocate(_defender, _target)
	_defender.core_location = _target


func _entity(display_name: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = display_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(e)
	return e


func _node() -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(n)
	return n


func _mod(op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"poison_stacks_per_hit"
	m.operation = op
	m.value = value
	return m


func _status(read_node: SkillNode, power: float) -> StatusInstance:
	var s := StatusInstance.new()
	s.def = _POISON
	s.power = power
	s.attacker = _attacker
	s.target = _target
	s.read_node = read_node
	return s


## Lands a fresh authored-[param power] poison read through [param read_node]
## on [param world] and returns the landed power.
func _land(read_node: SkillNode, power: float, world: CombatWorld = CombatWorld.live()) -> float:
	var s := _status(read_node, power)
	s.land_on(world.combat_for(_target), world)
	return s.power


func test_a_node_local_multiply_scales_only_that_nodes_landing() -> void:
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	assert_eq(_land(_blade, 3.0), 6.0, "the read node's local ×2 reaches the fold")
	assert_eq(_land(_sibling, 3.0), 3.0, "a sibling node's landing stays at the authored power")


func test_entity_flat_and_node_multiply_compose() -> void:
	_attacker.stat_board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	assert_eq(_land(_blade, 3.0), 8.0, "(3 + 1) × 2")
	assert_eq(_land(_sibling, 3.0), 4.0, "the entity +1 alone on the sibling")


func test_a_shadow_landing_reads_the_shadow_slice() -> void:
	var shadow := CombatWorld.shadow()
	assert_not_null(shadow.combat_for(_blade), "the shadow slice is minted before the live change")
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	assert_eq(_land(_blade, 3.0, shadow), 3.0, "the shadow folds its own snapshot, not the live node")
	assert_eq(_land(_blade, 3.0), 6.0, "the live landing folds the live node")


func test_a_resolved_power_lands_as_recorded() -> void:
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	var s := _status(_blade, 6.0)
	s.power_resolved = true
	s.land_on(_target.get_combat(), CombatWorld.live())
	assert_eq(s.power, 6.0, "a replay never folds a second time")


func test_no_read_node_falls_back_to_the_entity_board() -> void:
	_attacker.stat_board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	assert_eq(_land(null, 3.0), 4.0, "the entity board's +1, no node term")
