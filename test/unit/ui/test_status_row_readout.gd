extends GutTest

## #1191 (child of #1157 hub): the status row reads the whole floored stacks
## plus what next tick will actually land — `⌊row⌋` and
## [method StatusDef.next_tick_damage](host, power) from #1190, the SAME
## function the health-bar projection's first term uses, so the two agree.
## A damageless def (curse et al) shows just `⌊row⌋`, no dmg clause — the
## `%.2f` normalised text this replaces.
##
## Also covers [method ApplyStatusEffect.get_description]'s per-hit line,
## which folds through #1189's `def.stacks_per_hit(board, power)`.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _CURSE := preload("res://effects/status/curse.tres")
const _ROW_SCENE := preload("res://ui/tooltip_fan/status_row.tscn")

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
	_set_node_hp(10000.0)


func _combat() -> NodeCombat:
	return _node.get_combat()


func _set_node_hp(hp: float) -> void:
	_entity.stat_board.get_stat(&"node_health").base_value = hp
	_node.get_max_hp()
	(_node.node_board.get_stat(&"node_health") as PoolStat).set_current(hp)


func _set_res(stat_id: StringName, res: float) -> void:
	_entity.stat_board.get_stat(stat_id).base_value = res
	assert_almost_eq(float(_combat().get_local_value(stat_id)), res, 0.0001,
			"%s arranged at %s" % [stat_id, res])


func _row(status: NodeStatus, host) -> StatusRow:
	var row := _ROW_SCENE.instantiate() as StatusRow
	add_child_autofree(row)
	row.bind(status, host)
	return row


## The row's dmg number equals [method StatusDef.next_tick_damage] AND what
## one real tick actually lands on the same host — at two resistances.
func test_poison_row_dmg_matches_next_tick_damage_and_the_real_tick() -> void:
	for res in [0.0, 0.25]:
		_combat().clear_statuses()
		_set_res(&"poison_resistance", res)
		_combat().apply_status(_POISON, 12.7)
		var status: NodeStatus = _combat().get_statuses()[0]
		var expected: float = _POISON.next_tick_damage(_combat(), status.power)
		var row := _row(status, _combat())
		assert_string_contains(row._label.text, "%s" % [NumFmt.num(expected)],
				"res %s: row's dmg number matches next_tick_damage" % res)
		var before := _node.get_current_hp()
		_combat().tick_statuses()
		var landed := before - _node.get_current_hp()
		assert_almost_eq(landed, expected, 0.001,
				"res %s: the row's number is what actually lands" % res)


func test_poison_row_shows_the_floored_stacks() -> void:
	_combat().apply_status(_POISON, 12.7)
	var status: NodeStatus = _combat().get_statuses()[0]
	var row := _row(status, _combat())
	assert_string_contains(row._label.text, "12", "the floored row, not 12.7 or 12.70")


func test_curse_row_shows_floored_power_and_no_dmg_clause() -> void:
	_combat().apply_status(_CURSE, 5.4)
	var status: NodeStatus = _combat().get_statuses()[0]
	var row := _row(status, _combat())
	assert_string_contains(row._label.text, "5", "floored power shows")
	assert_false(row._label.text.contains("dmg"), "a damageless def shows no dmg clause")


func test_get_description_folds_stacks_per_hit_with_a_board_null_falls_back_to_authored() -> void:
	var effect := ApplyStatusEffect.new()
	effect.def = _POISON
	effect.power = 1.0
	assert_eq(effect.get_description(null, null), "Applies Poison (1 per hit).",
			"null board: the authored power lands unscaled")

	var board := _BOARD.duplicate(true) as EntityStatBoard
	var m := StatModifier.new()
	m.stat_id = &"poison_stacks_per_hit"
	m.operation = StatModifier.Operation.INCREASE
	m.value = 49.0
	board.add_modifier(m)
	assert_eq(effect.get_description(null, board), "Applies Poison (1.49 per hit).",
			"+49% poison_stacks_per_hit folds the per-hit line")
