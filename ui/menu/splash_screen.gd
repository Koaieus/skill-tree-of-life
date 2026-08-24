class_name SplashScreen
extends Control

## "Press any key" attract screen. Lives inside the same persistent meta_root
## scene as the frontmatter graph (not a separate SceneDirector destination) so
## a future pass can turn this into the literal root node of the menu's skill
## tree instead of a hard scene cut — that pass is #574.

signal advanced

var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var background := ColorRect.new()
	background.color = Color(0.03, 0.03, 0.05, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_label = Label.new()
	_label.text = "Skill Tree of Life\n\npress any key"
	_label.theme_type_variation = &"CinzelHeader"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 48)
	center.add_child(_label)

	var blink := create_tween().set_loops()
	blink.tween_property(_label, "modulate:a", 0.3, 1.0)
	blink.tween_property(_label, "modulate:a", 1.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key_event := event as InputEventKey
	var is_key_press := key_event != null and key_event.pressed and not key_event.echo
	if is_key_press:
		advanced.emit()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed:
		advanced.emit()
		accept_event()
