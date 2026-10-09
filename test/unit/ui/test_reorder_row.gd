extends GutTest

## #1516 — ReorderRow: a drop commits the new order as one `order_changed`
## (the permutation), a drop in place emits nothing, and `set_order` to the
## current order starts no tween.

const _ROW_SCENE := preload("res://ui/hud/command_tray/bodies/reorder_row.tscn")

var _row: ReorderRow


func before_each() -> void:
	_row = _ROW_SCENE.instantiate() as ReorderRow
	for k in [&"a", &"b", &"c", &"d"]:
		var c := Control.new()
		c.custom_minimum_size = Vector2(40, 60)
		c.set_meta(&"reorder_key", k)
		_row.add_child(c)
	add_child_autofree(_row)
	await get_tree().process_frame


func _item(i: int) -> Control:
	return _row.items()[i]


func test_slots_follow_child_order() -> void:
	assert_eq(_row.ids(), [&"a", &"b", &"c", &"d"] as Array[StringName])
	assert_eq(_item(2).position.x, 2 * (40.0 + _row.separation), "slot x = widths + gaps")
	assert_false(_row.is_animating(), "nothing glides at rest")


func test_dragging_the_third_card_to_the_first_slot_emits_that_permutation() -> void:
	watch_signals(_row)
	var third := _item(2)
	_row.begin_drag(third, third.position.x + 5.0)
	_row.drag_to(-20.0 + 5.0)
	assert_eq(_row.ids(), [&"c", &"a", &"b", &"d"] as Array[StringName], "neighbours slid aside live")
	assert_signal_not_emitted(_row, "order_changed", "nothing commits mid-drag")
	_row.end_drag()
	assert_signal_emitted_with_parameters(_row, "order_changed", [[&"c", &"a", &"b", &"d"] as Array[StringName]])


func test_a_drop_in_place_emits_nothing() -> void:
	watch_signals(_row)
	var second := _item(1)
	_row.begin_drag(second, second.position.x + 5.0)
	_row.drag_to(second.position.x + 10.0)
	_row.end_drag()
	assert_signal_not_emitted(_row, "order_changed")


func test_cancel_restores_the_press_order_silently() -> void:
	watch_signals(_row)
	var first := _item(0)
	_row.begin_drag(first, 5.0)
	_row.drag_to(500.0)
	assert_eq(_row.ids()[3], &"a")
	_row.cancel_drag()
	assert_eq(_row.ids(), [&"a", &"b", &"c", &"d"] as Array[StringName])
	assert_signal_not_emitted(_row, "order_changed")


func test_set_order_to_the_current_order_starts_no_tween() -> void:
	_row.set_order([&"a", &"b", &"c", &"d"] as Array[StringName], true)
	assert_false(_row.is_animating(), "nothing moved, nothing glides")
	_row.set_order([&"d", &"c", &"b", &"a"] as Array[StringName], true)
	assert_eq(_row.ids(), [&"d", &"c", &"b", &"a"] as Array[StringName])
	assert_true(_row.is_animating(), "a reorder glides")
