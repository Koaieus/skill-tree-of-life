## Toolbar row: one free-text `SpinBox` per id it's told to expose, plus a
## Reset button. Presentational only — holds no `StatBoard` reference of its
## own and no opinion on which ids are attributes; `StatBoardGraph` decides
## that (its `_OVERRIDE_IDS`) and calls `populate(ids)` once, right after
## instantiating this scene. `StatBoardGraph` also decides what a value
## change means (write the live board's `Stat.base_value`, in memory only)
## and what Reset means (re-read the authored values off disk) — this scene
## just renders controls and reports intent via signals.
##
## Instanced into `GraphEdit.get_menu_hbox()` by `stat_board_graph.gd`.
## Visibility is `StatBoardGraph`'s call too (#861): hidden whenever the
## loaded board has no `resource_path` — which is every board the runtime F3
## overlay ever shows (a live entity's board is always a `duplicate()`), so
## the controls never appear there without this scene needing to know why.
@tool
extends HBoxContainer

## 0…20000 — the observed runaway span (#760). Free-text `SpinBox` chosen
## over a slider: the range spans four orders of magnitude, so a linear
## slider would waste almost all its travel below 1000, and the acceptance
## spec's own worked example ("Setting STR to 1000") is a typed value, not a
## drag gesture.
const _RANGE_MAX := 20000.0

signal override_changed(id: StringName, value: float)
signal reset_requested()

var _spin_boxes: Dictionary = {}  # StringName -> SpinBox


## Build one Label + SpinBox pair per id, in order, followed by the Reset
## button. Call once, right after instantiating.
func populate(ids: Array) -> void:
	for id in ids:
		var lbl := Label.new()
		lbl.text = String(id).capitalize()
		lbl.add_theme_font_size_override(&"font_size", 10)
		add_child(lbl)

		var spin := SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = _RANGE_MAX
		spin.step = 1.0
		spin.custom_minimum_size = Vector2(64, 0)
		spin.tooltip_text = "Override %s (display only — never written to disk)" % id
		spin.value_changed.connect(_on_value_changed.bind(id))
		add_child(spin)
		_spin_boxes[id] = spin

	add_child(VSeparator.new())

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.tooltip_text = "Restore every attribute to its authored value (re-read from disk)"
	reset_btn.pressed.connect(func() -> void: reset_requested.emit())
	add_child(reset_btn)


func _on_value_changed(value: float, id: StringName) -> void:
	override_changed.emit(id, value)


## Reflect `value` in `id`'s SpinBox without re-emitting `override_changed` —
## used both when a board is first shown (display its authored values) and
## on Reset (display the values just restored from disk).
func set_displayed_value(id: StringName, value: float) -> void:
	var spin: SpinBox = _spin_boxes.get(id)
	if spin == null:
		return
	spin.set_block_signals(true)
	spin.value = value
	spin.set_block_signals(false)
