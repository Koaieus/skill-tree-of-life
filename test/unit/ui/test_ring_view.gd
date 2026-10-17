extends GutTest
## RingView: per-cell state follows RingTable.can_buy, the selected cell is
## marked, and a click on a cell reports its node name (empty = none).

const _SCENE := preload("res://ui/ring/ring_view.tscn")

var _view: RingView
var _table: RingTable


func before_each() -> void:
	_view = _SCENE.instantiate()
	_view.size = Vector2(800, 600)
	add_child_autofree(_view)
	await get_tree().process_frame
	await get_tree().process_frame
	_table = RingTable.sample(_view.display_graph())


func _first_buyable() -> StringName:
	return _table.buyable([] as Array[StringName])[0]


func test_states_follow_can_buy() -> void:
	var spent: Array[StringName] = [_first_buyable()]
	_view.show_state(_table, spent, &"")
	assert_gt(_table.cells().size(), 0)
	for c in _table.cells():
		var want := RingView.State.LOCKED
		if spent.has(c):
			want = RingView.State.BOUGHT
		elif _table.can_buy(spent, c):
			want = RingView.State.BUYABLE
		assert_eq(_view.state_of(c), want, "state of %s" % c)
	assert_ne(_table.buyable(spent).size(), 0, "fixture should leave buyable cells")


func test_selected_cell_is_marked() -> void:
	var cell := _first_buyable()
	_view.show_state(_table, [] as Array[StringName], cell)
	assert_eq(_view.selected_cell(), cell)
	_view.show_state(_table, [] as Array[StringName], &"")
	assert_eq(_view.selected_cell(), &"")


func test_click_reports_cell_name() -> void:
	_view.show_state(_table, [] as Array[StringName], &"")
	var cell := _first_buyable()
	var at := _view.cell_local_position(cell)
	assert_eq(_view.cell_at(at), cell, "hit-test maps the cell's own position back to it")
	assert_eq(_view.cell_at(Vector2(-10000, -10000)), &"", "a miss is the empty name")
	assert_eq(_view.cell_at(_view.cell_local_position(_table.centre())), &"",
		"the core is inert, never a cell")
	watch_signals(_view)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	_view._gui_input(ev)
	assert_signal_emitted_with_parameters(_view, "cell_clicked", [cell])
