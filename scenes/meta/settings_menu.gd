class_name SettingsMenu
extends Control

## Builds its rows by walking GameSettings.get_property_list() — @export_group
## gives sections, hint/hint_string gives widget bounds. Write the
## widget-per-hint switch here ONCE; adding a setting to GameSettings must
## never require touching this scene again.
##
## The row SHAPE — the HBox, the label, its column width, the slot the widget
## drops into — is authored in `settings_row.tscn` (#609); only the row COUNT
## and the widget PICK stay reflective, which is where reflection earns its
## keep. `%Widget` in that scene authors the slot's default size flag
## (`SIZE_EXPAND_FILL`, so a slider or a LineEdit takes the row's slack); a
## `CheckBox` or an `OptionButton` would stretch absurdly at that flag, so
## `_make_widget` overrides it to `SIZE_SHRINK_BEGIN` on those two only.

const _ROW_SCENE := preload("res://scenes/meta/settings_row.tscn")

@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()

	var settings: GameSettings = Settings.current
	var current_group := ""
	for prop in settings.get_property_list():
		if prop.usage & PROPERTY_USAGE_GROUP:
			current_group = prop.name
			_rows.add_child(_make_section_label(current_group))
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		_rows.add_child(_make_row(prop))


func _make_section_label(title: String) -> Label:
	var label := Label.new()
	label.text = title
	return label


func _make_row(prop: Dictionary) -> Control:
	var row: HBoxContainer = _ROW_SCENE.instantiate()

	var label := row.get_node("%Label") as Label
	label.text = String(prop.name)

	var key := StringName(prop.name)
	var widget := _make_widget(prop, key)

	# The slot's own size flag is the default a widget gets — but only if its
	# per-type branch above didn't already claim one of its own (CheckBox,
	# OptionButton); Control's own stock default is SIZE_FILL, so anything
	# still sitting at that means _make_widget left it alone.
	var slot := row.get_node("%Widget") as Control
	if widget.size_flags_horizontal == Control.SIZE_FILL:
		widget.size_flags_horizontal = slot.size_flags_horizontal
	var slot_index := slot.get_index()
	row.remove_child(slot)
	slot.queue_free()
	row.add_child(widget)
	row.move_child(widget, slot_index)

	return row


func _make_widget(prop: Dictionary, key: StringName) -> Control:
	var value = Settings.get_value(key)

	if prop.type == TYPE_BOOL:
		var check := CheckBox.new()
		check.button_pressed = value
		check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # not the slot's default EXPAND_FILL — a row-wide hit area
		check.toggled.connect(func(v: bool): Settings.set_value(key, v))
		return check

	if prop.hint == PROPERTY_HINT_ENUM:
		var option := OptionButton.new()
		var names: PackedStringArray = String(prop.hint_string).split(",")
		for i in names.size():
			option.add_item(names[i], i)
		option.selected = int(value)
		option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # not the slot's default EXPAND_FILL — stretches absurdly
		option.item_selected.connect(func(idx: int): Settings.set_value(key, idx))
		return option

	if prop.hint == PROPERTY_HINT_RANGE:
		var bounds: PackedStringArray = String(prop.hint_string).split(",")
		var slider := HSlider.new()
		slider.min_value = float(bounds[0])
		slider.max_value = float(bounds[1])
		slider.step = float(bounds[2]) if bounds.size() > 2 else 0.01
		slider.custom_minimum_size = Vector2(160, 0)
		slider.value = value
		slider.value_changed.connect(func(v: float): Settings.set_value(key, v))
		return slider

	var line_edit := LineEdit.new()
	line_edit.text = str(value)
	line_edit.text_submitted.connect(func(v: String): Settings.set_value(key, v))
	return line_edit
