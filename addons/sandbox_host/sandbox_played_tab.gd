@tool
class_name SandboxPlayedTab
extends SandboxTab
## A PLAYED tab: a non-@tool gameplay showcase scene. It can't run in-editor —
## the systems are deliberately NOT @tool — so this is a launch card: a title,
## a description, and a "▶ Run" button that plays the scene through the editor.
## (Embedding it in a SubViewport would dead-end at @tool-ing the systems, the
## rejected branch — see docs/domain/sandbox-framework.md.)

var _title: String
var _scene_path: String
var _description: String


func setup(title: String, scene_path: String, description: String) -> void:
	_title = title
	_scene_path = scene_path
	_description = description
	_build()


func get_tab_title() -> String:
	return _title


func get_mode() -> Mode:
	return Mode.PLAYED


func _build() -> void:
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 16)
	center.add_child(box)

	var heading := Label.new()
	heading.text = _title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override(&"font_size", 22)
	box.add_child(heading)

	var desc := Label.new()
	desc.text = _description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(440, 0)
	box.add_child(desc)

	var run := Button.new()
	run.text = "  ▶  Run showcase  "
	run.tooltip_text = "Play %s — a non-@tool gameplay scene; it runs the real systems on play, not in-editor." % _scene_path
	run.size_flags_horizontal = SIZE_SHRINK_CENTER
	run.pressed.connect(_on_run_pressed)
	box.add_child(run)

	var hint := Label.new()
	hint.text = _scene_path
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.5)
	box.add_child(hint)


func _on_run_pressed() -> void:
	EditorInterface.play_custom_scene(_scene_path)
