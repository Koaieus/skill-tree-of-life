extends GutTest

## OwnerPanel's attribute rows colour a volatile stat with Emissive.VOLATILE,
## asked of the owner's board (StatBoard.is_stat_volatile); a plain one stays plain.

const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _PANEL_SCENE := preload("res://ui/tooltip_fan/panels/owner_panel.tscn")


func _row_for(panel: Node, display_name: String) -> StatValueRow:
	for row in panel.get_node("%Rows").get_children():
		if row is StatValueRow and row.get_node("%NameLabel").text == display_name:
			return row
	return null


func test_volatile_attribute_row_is_violet_and_plain_one_stays_plain() -> void:
	var graph := TestWorld.create(self).graph
	var entity: Entity = _ENTITY_SCENE.instantiate()
	entity.stat_board = TestBoards.flat_entity_board()
	graph.entities_container.add_child(entity)
	var node := TestWorld.around(graph).add_node()
	node.owned_by = entity

	var flip := StatModifier.new()
	flip.stat_id = &"strength"
	flip.operation = StatModifier.Operation.MULTIPLY
	flip.value = -1.0
	entity.stat_board.add_modifier(flip)

	var panel: OwnerPanel = _PANEL_SCENE.instantiate()
	add_child_autofree(panel)
	panel.bind(node, graph)

	var strength := _row_for(panel, StatRegistry.get_def(&"strength").display_name)
	var dexterity := _row_for(panel, StatRegistry.get_def(&"dexterity").display_name)
	assert_not_null(strength, "precondition: a strength row")
	assert_not_null(dexterity, "precondition: a dexterity row")
	assert_true(strength.value_volatile, "strength carries a x-1 — volatile")
	assert_eq(strength.get_node("%ValueLabel").get_theme_color(&"font_color"), Emissive.VOLATILE)
	assert_false(dexterity.value_volatile, "dexterity has no volatile modifier")
	assert_false(dexterity.get_node("%ValueLabel").has_theme_color_override(&"font_color"))
