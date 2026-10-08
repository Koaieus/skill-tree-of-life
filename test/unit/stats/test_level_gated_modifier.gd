extends GutTest

## LevelGatedModifier: absent below unlock_level, authored value outright at
## and above it, on the board path and the scaled_copy path.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _node: SkillNode


func _fresh_node() -> void:
	if is_instance_valid(_node):
		_node.free()
	var graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = TestBoards.flat_entity_board()
	graph.add_child(entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(_node)
	await get_tree().process_frame
	_node.stake_level = 8


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func _gated(op: StatModifier.Operation, value: float, unlock: int) -> LevelGatedModifier:
	var m := LevelGatedModifier.new()
	m.stat_id = &"armor"
	m.operation = op
	m.value = value
	m.unlock_level = unlock
	return m


func _read_at(level: int) -> float:
	_node.allocation_level = level
	return _node.get_local_value(&"armor")


func test_multiply_is_absent_below_the_gate_and_round_trips() -> void:
	for unlock in [2, 4]:
		await _fresh_node()
		_node.allocation_level = 1
		var flat := StatModifier.new()
		flat.stat_id = &"armor"
		flat.value = 10.0
		flat.operation = StatModifier.Operation.ADD_BASE
		_node.add_local_modifier(flat)
		_node.add_local_modifier(_gated(StatModifier.Operation.MULTIPLY, 2.0, unlock))
		var base: float = _read_at(1)
		assert_gt(base, 0.0, "nonzero base so the multiply has teeth")
		for pass_n in 2:
			for lvl in range(1, 7):
				var expect: float = base * lvl * (2.0 if lvl >= unlock else 1.0)
				assert_almost_eq(_read_at(lvl), expect, 0.001, "unlock %d level %d pass %d" % [unlock, lvl, pass_n])
			_read_at(1)


func test_add_base_is_zero_below_the_gate_and_flat_at_and_above() -> void:
	for unlock in [2, 4]:
		await _fresh_node()
		_node.allocation_level = 1
		_node.add_local_modifier(_gated(StatModifier.Operation.ADD_BASE, 5.0, unlock))
		var base: float = _read_at(1) - (5.0 if 1 >= unlock else 0.0)
		for lvl in range(1, 7):
			var expect: float = 5.0 if lvl >= unlock else 0.0
			assert_almost_eq(_read_at(lvl) - base, expect, 0.001, "unlock %d level %d" % [unlock, lvl])


func test_scaled_copy_gates_the_same() -> void:
	var mutator := LocalScaleMutator.new()
	for unlock in [2, 4]:
		var mul := _gated(StatModifier.Operation.MULTIPLY, 2.0, unlock)
		var add := _gated(StatModifier.Operation.ADD_BASE, 5.0, unlock)
		for lvl in range(1, 7):
			var gate: bool = lvl >= unlock
			assert_almost_eq(mutator.scaled_copy(mul, 1, lvl).value, 2.0 if gate else 1.0, 0.001, "mul unlock %d lvl %d" % [unlock, lvl])
			assert_almost_eq(mutator.scaled_copy(add, 1, lvl).value, 5.0 if gate else 0.0, 0.001, "add unlock %d lvl %d" % [unlock, lvl])


func test_format_names_the_gate() -> void:
	var m := _gated(StatModifier.Operation.ADD_BASE, 5.0, 4)
	assert_string_contains(m.format(), "at 4/X")
