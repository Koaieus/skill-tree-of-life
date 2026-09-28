extends GutTest

## A parent stat (ADR 0029) minted on a node board renders its fold terms in
## the node stats panel — "+20% increased" — and never a number of its own.
## A child read on that node already folds the entity's parent bins.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _PANEL_SCENE := preload("res://ui/tooltip_fan/panels/node_stats_panel.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _mod(stat_id: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


func _node() -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(node)
	return node


## Every Label's text under [param row] the player can see (visible and not
## faded to zero alpha, e.g. an idle delta chip), joined.
func _row_text(row: Node) -> String:
	var parts: PackedStringArray = []
	for label in row.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree() and _alpha_to(label, row) > 0.0:
			parts.append((label as Label).text)
	return " ".join(parts)


func _alpha_to(item: CanvasItem, root: Node) -> float:
	var a := 1.0
	var n: Node = item
	while n != null and n != root:
		if n is CanvasItem:
			a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	return a


func _rows_text(panel: NodeStatsPanel) -> PackedStringArray:
	var out: PackedStringArray = []
	var rows := panel.find_child("Rows", true, false)
	for row in rows.get_children():
		out.append(_row_text(row))
	return out


func test_minted_parent_renders_its_terms_never_a_value() -> void:
	var node := _node()
	node.add_local_modifier(_mod(&"damage", StatModifier.Operation.INCREASE, 20.0))
	var panel: NodeStatsPanel = _PANEL_SCENE.instantiate()
	add_child_autofree(panel)
	panel.bind(node, _graph)
	var name := StatRegistry.get_def(&"damage").display_name
	var damage_row := ""
	for text in _rows_text(panel):
		if text.begins_with(name + " ") or text == name:
			damage_row = text
	assert_ne(damage_row, "", "the panel lists a %s row" % name)
	assert_string_contains(damage_row, "20%")
	assert_false(damage_row.contains("%s 0" % name), "never '%s 0'" % name)
	assert_false(damage_row.contains("+0"), "no own value rendered")


func test_child_read_folds_the_entity_parent_increase() -> void:
	var node := _node()
	var e: Entity = autofree(Entity.new())
	e.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(e)
	await get_tree().process_frame
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(e, node)
	node.add_local_modifier(_mod(&"blade_damage", StatModifier.Operation.ADD_BASE, 99.0))
	var before := float(node.get_local_value(&"blade_damage"))
	# INT stat: pick a base the +20% scales to a whole number (100 → 120).
	assert_gt(before, 0.0, "arrangement: a local blade_damage to scale")
	e.stat_board.add_modifier(_mod(&"damage", StatModifier.Operation.INCREASE, 20.0))
	assert_almost_eq(float(node.get_local_value(&"blade_damage")), before * 1.2, 0.0001,
			"entity +20% damage folds into the node-local blade_damage")
