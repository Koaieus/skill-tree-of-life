extends GutTest

## #880: NodeVisualsComposite's modulate refreshes automatically as statuses
## are applied/ticked/removed on the node's own NodeCombat slice — no manual
## poke from the test. Fixture copied from test_node_combat_status.gd.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


class SpyDef:
	extends StatusDef


var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node
	await get_tree().process_frame


func _def(id: StringName, power_max: float, decay: float = 1.0,
		reapply := StatusDef.Reapply.REFRESH) -> SpyDef:
	var d := SpyDef.new()
	d.id = id
	d.power_max = power_max
	d.decay_per_tick = decay
	d.reapply = reapply
	d.tint = Color(0.2, 0.85, 0.25, 1.0)
	return d


func _composite() -> Node2D:
	return _node.find_child("NodeVisualsComposite", true, false)


func test_apply_refreshes_modulate_with_no_manual_poke() -> void:
	var d := _def(&"poison", 4.0)
	_node.get_combat().apply_status(d, 4.0)
	assert_true(_composite().modulate.is_equal_approx(d.tint), "power 4 of 4 is a full blend, applied automatically")


func test_tick_decay_refreshes_modulate() -> void:
	var d := _def(&"poison", 4.0, 1.0)
	_node.get_combat().apply_status(d, 4.0)
	_node.get_combat().tick_statuses()
	assert_true(_composite().modulate.is_equal_approx(Color.WHITE.lerp(d.tint, 3.0 / 4.0)),
		"decay to power 3 of 4 re-blends automatically on tick")


func test_remove_restores_base_modulate() -> void:
	var d := _def(&"poison", 4.0, 4.0)
	_node.get_combat().apply_status(d, 4.0)
	_node.get_combat().remove_status(&"poison")
	assert_true(_composite().modulate.is_equal_approx(Color.WHITE), "removing the only status restores WHITE")


func test_strongest_status_wins_and_ties_take_the_first_applied() -> void:
	var weak := _def(&"blind", 4.0)
	weak.tint = Color(0.85, 0.85, 0.35, 1.0)
	var strong := _def(&"poison", 4.0)
	strong.tint = Color(0.2, 0.85, 0.25, 1.0)

	_node.get_combat().apply_status(weak, 1.0)
	_node.get_combat().apply_status(strong, 4.0)
	assert_true(_composite().modulate.is_equal_approx(strong.tint), "the strongest normalised power wins")

	var tie_a := _def(&"a_tie", 4.0)
	tie_a.tint = Color(1.0, 0.0, 0.0, 1.0)
	var tie_b := _def(&"b_tie", 4.0)
	tie_b.tint = Color(0.0, 0.0, 1.0, 1.0)
	_node.get_combat().clear_statuses()
	_node.get_combat().apply_status(tie_a, 2.0)
	_node.get_combat().apply_status(tie_b, 2.0)
	assert_true(_composite().modulate.is_equal_approx(Color.WHITE.lerp(tie_a.tint, 0.5)),
		"a tie in normalised power (0.5 each) takes the first-applied status's colour")
