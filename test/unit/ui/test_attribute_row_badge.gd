extends GutTest

## An attribute row leads with its stat's [IdentityBadge], resolved from
## [member AttributeRow.attr_id] through [StatRegistry] — no swatch dot.

const _ROW_SCENE := preload("res://ui/hud/attributes_panel/attribute_row.tscn")


func _row(attr_id: StringName) -> AttributeRow:
	var row: AttributeRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.attr_id = attr_id
	return row


func _badges(row: AttributeRow) -> Array[Node]:
	return row.find_children("*", "IdentityBadge", true, false)


func test_a_strength_row_shows_strengths_identity_badge() -> void:
	var row := _row(&"strength")
	var badges := _badges(row)
	assert_eq(badges.size(), 1, "one identity badge")
	if badges.is_empty():
		return
	var badge := badges[0] as IdentityBadge
	var def := StatRegistry.get_def(&"strength")
	assert_not_null(def.identity, "strength has an identity")
	assert_eq(badge.identity, def.identity, "bound to the stat identity")
	assert_eq(badge.size_px, row.badge_px, "sized by the row's knob")
	assert_eq(row.get_child(0), badge, "the badge leads the row")


func test_no_swatch_dot_remains() -> void:
	var row := _row(&"strength")
	assert_null(row.find_child("Dot", true, false), "the dot is gone")


func test_an_unknown_attr_id_leaves_the_badge_unbound() -> void:
	var row := _row(&"no_such_stat")
	var badges := _badges(row)
	if not badges.is_empty():
		assert_null((badges[0] as IdentityBadge).identity, "no def, no identity")
