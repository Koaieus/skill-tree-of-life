extends GutTest

## The shipped stat families (ADR 0029): a modifier on a parent — `damage`,
## `attributes`, `status_resistance` — reaches every child through the child's own
## read, on the real default entity board. The Ninja's Phantom Strike is the
## node-local absent-child path: the aura grants `damage` on the node board,
## which carries no `blade_damage` of its own.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _NINJA := preload("res://entity/core/ninja_core.tres")

const _DAMAGE_CHILDREN: Array[StringName] = [&"blade_damage", &"spell_damage", &"ranged_damage"]
const _ATTRIBUTE_CHILDREN: Array[StringName] = [
	&"strength", &"dexterity", &"intelligence", &"wisdom", &"constitution", &"perception"]
const _RESISTANCE_CHILDREN: Array[StringName] = [
	&"poison_resistance", &"corruption_resistance", &"curse_resistance", &"blindness_resistance"]

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _entity(core: CoreClass = null) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = TestBoards.flat_entity_board()
	if core != null:
		e.core_class = core
	_graph.add_child(e)
	return e


func _mod(stat_id: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


func _values(board: StatBoard, ids: Array[StringName]) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = float(board.get_value(id))
	return out


func test_increased_damage_moves_every_damage_type_by_the_same_factor() -> void:
	var b := _entity().stat_board
	for id in _DAMAGE_CHILDREN:
		b.get_stat(id).base_value = 50.0
	var before := _values(b, _DAMAGE_CHILDREN)
	b.add_modifier(_mod(&"damage", StatModifier.Operation.INCREASE, 20.0))
	for id in _DAMAGE_CHILDREN:
		assert_almost_eq(float(b.get_value(id)), floorf(before[id] * 1.2 + 0.0001), 0.0001,
				"%s x 1.2 through the family" % id)


func test_flat_attributes_add_to_each_of_the_six() -> void:
	var b := _entity().stat_board
	var before := _values(b, _ATTRIBUTE_CHILDREN)
	b.add_modifier(_mod(&"attributes", StatModifier.Operation.ADD_BASE, 1.0))
	for id in _ATTRIBUTE_CHILDREN:
		assert_almost_eq(float(b.get_value(id)), before[id] + 1.0, 0.0001, "%s +1" % id)


func test_status_resistance_reaches_every_resistance() -> void:
	var b := _entity().stat_board
	var before := _values(b, _RESISTANCE_CHILDREN)
	b.add_modifier(_mod(&"status_resistance", StatModifier.Operation.ADD_BASE, 0.05))
	for id in _RESISTANCE_CHILDREN:
		assert_almost_eq(float(b.get_value(id)), before[id] + 0.05, 0.0001, "%s +0.05" % id)


func test_ninja_phantom_strike_is_one_family_flat() -> void:
	var strike: AuraEffect = null
	for e in _NINJA.effects:
		if e is AuraEffect and (e as AuraEffect).display_name == "Phantom Strike":
			strike = e as AuraEffect
	assert_not_null(strike, "the Phantom Strike aura")
	assert_eq(strike.modifiers.size(), 1, "one family modifier, not three per-type ones")
	var m: StatModifier = strike.modifiers[0]
	assert_eq(m.stat_id, &"damage")
	assert_eq(m.operation, StatModifier.Operation.ADD_BASE)
	assert_almost_eq(m.value, 5.0, 0.0001)


func test_ninja_core_node_reads_plus_five_on_every_damage_type() -> void:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(node)
	var e := _entity(_NINJA)
	await get_tree().process_frame
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(e, node)
	e.core_location = node
	assert_true(node.node_board == null or node.node_board.get_stat(&"blade_damage") == null,
			"arrangement: the node has no blade_damage of its own")
	for id in _DAMAGE_CHILDREN:
		var baseline := float(e.stat_board.get_value(id))
		assert_almost_eq(float(node.get_local_value(id)) - baseline, 5.0, 0.0001, "%s +5 at hop 0" % id)
