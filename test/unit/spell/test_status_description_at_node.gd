extends GutTest

## A status describer read for a node folds `<family>_stacks_per_hit` through
## that node's slice exactly as [method StatusInstance.land_on] does — entity
## bins, the node's local bins, the authored power — so the tooltip line over a
## node carrying a local bonus says what a hit read there lands. No node keeps
## the caster-board reading.

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


func _line(stacks: float) -> String:
	return "Applies Poison (%s per hit)." % NumFmt.num(stacks)


func _effect(power: float) -> ApplyStatusEffect:
	var eff := ApplyStatusEffect.new()
	eff.def = _POISON
	eff.power = power
	return eff


func test_the_description_at_a_node_says_what_landing_there_applies() -> void:
	_attacker.stat_board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	var landed := _land(_blade, 3.0)
	assert_eq(landed, 8.0, "fixture: (3 + 1) x 2 lands at the blade")
	assert_eq(_effect(3.0).get_description(null, _attacker.stat_board, _blade), _line(landed))
	assert_eq(_effect(3.0).get_description(null, _attacker.stat_board, _sibling), _line(_land(_sibling, 3.0)),
			"a sibling without the local bonus reads the entity board alone")


func test_with_no_node_the_description_keeps_the_entity_board_reading() -> void:
	_attacker.stat_board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	assert_eq(_effect(3.0).get_description(null, _attacker.stat_board), _line(_land(null, 3.0)))


func test_an_affinity_described_at_a_node_folds_the_same_slice() -> void:
	_blade.add_local_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	var aff := SpellAffinity.new()
	aff.status = _POISON
	aff.innate = 3
	aff.rate = 0.0
	assert_eq(aff.get_description(_attacker.stat_board, _blade),
			"Applies Poison (%s per hit; refuses poison infusions)." % NumFmt.num(_land(_blade, 3.0)))
