extends GutTest

## Sharp tests for LocalStat — factory construction, pipeline composition,
## SET tiebreak entity-vs-local, fallback when entity board lacks the stat,
## add/remove local modifier, and owner rebind through SkillNode.
##
## Pipeline: (base + Σ ADD_BASE) × (1 + Σ INCREASE/100) × Π MULTIPLY + Σ ADD_BONUS
## LocalStat merges entity.bins + self.bins before ONE pipeline run —
## chaining pipelines would double-apply INCREASE against MULTIPLY.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _board() -> StatBoard:
	return _BOARD.duplicate(true)


func _mod(op: int, value: float, id: StringName = &"strength") -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	return m


func _entity(board: StatBoard) -> Entity:
	var e := Entity.new()
	autofree(e)
	e.display_name = "Test"
	e.stat_board = board
	return e


# ── Factory ─────────────────────────────────────────────────────────────────

func test_factory_for_stat_with_entity_stat() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	var ls := LocalStat.for_stat(board.strength)
	assert_eq(ls.definition, board.strength.definition)
	assert_eq(ls.entity_stat, board.strength)


func test_factory_for_stat_with_definition_only() -> void:
	var def: StatDef = StatRegistry.get_def(&"strength")
	var ls := LocalStat.for_stat(null, def, 42.0)
	assert_eq(ls.definition, def)
	assert_eq(ls.entity_stat, null)
	assert_eq(ls.base_value, 42.0)
	assert_eq(ls.get_value(), 42)


# ── Passthrough (no local modifiers) ────────────────────────────────────────

func test_entity_stat_passthrough_plain() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	var ls := LocalStat.for_stat(board.strength)
	assert_eq(ls.get_value(), 10)


func test_entity_stat_passthrough_with_modifiers() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	var ls := LocalStat.for_stat(board.strength)
	assert_eq(ls.get_value(), 15)


# ── Combined pipeline ───────────────────────────────────────────────────────

func test_combined_entity_plus_local_add_base() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	var ls := LocalStat.for_stat(board.strength)
	ls.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 3.0))
	# (10 + 5 + 3) = 18
	assert_eq(ls.get_value(), 18)


func test_combined_entity_plus_local_increase() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	var ls := LocalStat.for_stat(board.strength)
	ls.add_modifier(_mod(StatModifier.Operation.INCREASE, 50.0))
	# (10+5) × 1.5 = 22.5 → roundi half-away-from-zero → 23
	assert_eq(ls.get_value(), 23)


func test_combined_entity_plus_local_multiply() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	var ls := LocalStat.for_stat(board.strength)
	ls.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	# (10+5) × 2 = 30
	assert_eq(ls.get_value(), 30)


func test_combined_entity_plus_local_add_bonus() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	board.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	var ls := LocalStat.for_stat(board.strength)
	ls.add_modifier(_mod(StatModifier.Operation.ADD_BONUS, 7.0))
	# 10 × 2 + 7 = 27
	assert_eq(ls.get_value(), 27)


# ── SET tiebreak ────────────────────────────────────────────────────────────

func test_set_tiebreak_local_wins_at_equal_priority() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	board.add_modifier(_mod(StatModifier.Operation.SET, 50.0))
	var ls := LocalStat.for_stat(board.strength)
	ls.add_modifier(_mod(StatModifier.Operation.SET, 99.0))
	# equal priority (0), local SET wins = 99
	assert_eq(ls.get_value(), 99)


func test_set_entity_higher_priority_trumps_local() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	var entity_set := _mod(StatModifier.Operation.SET, 50.0)
	entity_set.priority = 10
	board.add_modifier(entity_set)
	var ls := LocalStat.for_stat(board.strength)
	var local_set := _mod(StatModifier.Operation.SET, 99.0)
	local_set.priority = 1
	ls.add_modifier(local_set)
	# entity priority 10 > local priority 1 → 50
	assert_eq(ls.get_value(), 50)


func test_set_tiebreak_second_local_still_wins_last() -> void:
	# Two local SETs at equal priority — last-in wins.
	var board := _board()
	board.strength.base_value = 10.0
	var ls := LocalStat.for_stat(board.strength)
	ls.add_modifier(_mod(StatModifier.Operation.SET, 33.0))
	ls.add_modifier(_mod(StatModifier.Operation.SET, 77.0))
	assert_eq(ls.get_value(), 77)


# ── Fallback: entity board lacks the stat ────────────────────────────────────

func test_standalone_local_stat_without_entity_uses_own_base() -> void:
	var def: StatDef = StatRegistry.get_def(&"node_health")
	# node_health.default_value is 10.0
	var ls := LocalStat.for_stat(null, def, def.default_value)
	ls.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0, &"node_health"))
	# (10 + 5) = 15
	assert_eq(ls.get_value(), 15)


func test_standalone_local_stat_set_works() -> void:
	var def: StatDef = StatRegistry.get_def(&"node_health")
	var ls := LocalStat.for_stat(null, def, def.default_value)
	ls.add_modifier(_mod(StatModifier.Operation.SET, 77.0, &"node_health"))
	assert_eq(ls.get_value(), 77)


# ── Add / remove local modifier ─────────────────────────────────────────────

func test_add_remove_local_modifier_restores_entity_value() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	var ls := LocalStat.for_stat(board.strength)
	var local_mod := _mod(StatModifier.Operation.INCREASE, 50.0)
	ls.add_modifier(local_mod)
	# (10+5) × 1.5 = 22.5 → roundi → 23
	assert_eq(ls.get_value(), 23)
	ls.remove_modifier(local_mod)
	# back to 15
	assert_eq(ls.get_value(), 15)


# ── Signal chain ────────────────────────────────────────────────────────────

func test_value_changed_fires_on_entity_stat_value_change() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	var ls := LocalStat.for_stat(board.strength)
	watch_signals(ls)
	board.strength.base_value = 20.0
	assert_signal_emitted(ls, "value_changed")


func test_value_changed_fires_when_entity_adds_modifier() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	var ls := LocalStat.for_stat(board.strength)
	watch_signals(ls)
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	assert_signal_emitted(ls, "value_changed")


func test_value_changed_fires_when_local_adds_modifier() -> void:
	var board := _board()
	board.strength.base_value = 10.0
	var ls := LocalStat.for_stat(board.strength)
	watch_signals(ls)
	ls.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	assert_signal_emitted(ls, "value_changed")


# ── Integration: SkillNode.get_local_stat ────────────────────────────────────

func test_skill_node_get_local_stat_returns_same_instance() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board := _board()
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = "N0"
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)

	var a := node.get_local_stat(&"strength")
	var b := node.get_local_stat(&"strength")
	assert_eq(a, b, "same stat_id must return the same cached LocalStat")


func test_skill_node_get_local_stat_reads_entity_value() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board := _board()
	board.strength.base_value = 17.0
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)
	await get_tree().process_frame

	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = "N0"
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)

	var ls := node.get_local_stat(&"strength")
	assert_eq(ls.get_value(), 17)


func test_skill_node_local_stat_rebinds_after_realloc() -> void:
	# Allocate to entity A (STR=100), dealloc, realloc to entity B (STR=200).
	# The cached LocalStat must follow the new owner.
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var board_a := _board()
	board_a.strength.base_value = 100.0
	var entity_a: Entity = autofree(Entity.new())
	entity_a.stat_board = board_a
	graph.add_child(entity_a)

	var board_b := _board()
	board_b.strength.base_value = 200.0
	var entity_b: Entity = autofree(Entity.new())
	entity_b.stat_board = board_b
	graph.add_child(entity_b)

	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = "N0"
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)

	alloc.force_allocate(entity_a, node)
	var ls := node.get_local_stat(&"strength")
	assert_eq(ls.get_value(), 100)

	alloc.force_deallocate(node)
	alloc.force_allocate(entity_b, node)
	assert_eq(ls.get_value(), 200)


func test_skill_node_local_stat_with_addon_modifier() -> void:
	# Simulate the addon path: get_local_stat + add_modifier → value updates.
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board := _board()
	board.strength.base_value = 10.0
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)
	await get_tree().process_frame

	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = "N0"
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)

	var ls := node.get_local_stat(&"strength")
	ls.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	# entity base 10 + entity mod 0 + local mod +5 = 15
	assert_eq(ls.get_value(), 15)
