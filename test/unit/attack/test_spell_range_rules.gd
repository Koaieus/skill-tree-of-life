extends GutTest

## SpellRangeRules.bonus_hops() — flat-int sibling of multiplier(), same
## 3-tier fallback (node-local -> board preview -> 0). Feeds HopRangeFinder
## only, never PropagationConfig.max_hops (#727).

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _node() -> SkillNode:
	var node := _NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(node)
	return node


func _static_mod(id: StringName, op: int, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op as StatModifier.Operation
	m.value = value
	return m


func test_null_attacker_gets_no_bonus_even_with_a_local_source_modifier() -> void:
	var node := _node()
	node.add_local_modifier(_static_mod(&"spell_hops", StatModifier.Operation.ADD_BASE, 5.0))

	assert_eq(SpellRangeRules.bonus_hops(null, node), 0,
			"a null attacker must not inherit a source node's local spell_hops — auras don't scale")


func test_source_local_value_wins_when_attacker_and_source_are_both_present() -> void:
	var node := _node()
	node.add_local_modifier(_static_mod(&"spell_hops", StatModifier.Operation.ADD_BASE, 5.0))
	var attacker: Entity = autofree(Entity.new())

	assert_eq(SpellRangeRules.bonus_hops(attacker, node), 5)


func test_board_preview_path_used_when_no_source_node() -> void:
	var board: EntityStatBoard = preload("res://entity/default_entity_board.tres").duplicate(true)
	var mod := StatModifier.new()
	mod.stat_id = &"spell_hops"
	mod.operation = StatModifier.Operation.SET
	mod.value = 4.0
	board.add_modifier(mod)

	assert_eq(SpellRangeRules.bonus_hops(null, null, board), 4)


func test_falls_back_to_zero_with_neither_source_nor_board() -> void:
	assert_eq(SpellRangeRules.bonus_hops(null, null, null), 0)


func test_node_local_bonus_stacks_over_entity_board_value() -> void:
	var graph := preload("res://graph/graph.tscn").instantiate()
	add_child_autofree(graph)
	var board: EntityStatBoard = preload("res://entity/default_entity_board.tres").duplicate(true)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var node := _NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(node)
	autofree(node)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)

	# Baseline INT (10) is well below the spell_hops ladder's first breakpoint
	# (50), so the entity board alone contributes 0.
	assert_eq(SpellRangeRules.bonus_hops(entity, node), 0)

	node.add_local_modifier(_static_mod(&"spell_hops", StatModifier.Operation.ADD_BASE, 2.0))

	assert_eq(SpellRangeRules.bonus_hops(entity, node), 2,
			"a node-local spell_hops modifier stacks over the entity-board baseline")
