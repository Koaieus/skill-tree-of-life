@tool
class_name SandboxPlayedTab
extends SandboxTab
## A PLAYED tab: a non-@tool gameplay showcase scene. It can't run in-editor —
## the systems are deliberately NOT @tool — so this is a launch card: a title,
## a description, an optional preview thumbnail, and a "▶ Run" button that plays
## the scene through the editor. (A SubViewport live-embed would dead-end at
## @tool-ing the systems, the rejected branch — see the design doc.)
##
## Authored as a scene in `addons/sandbox_host/tabs/`; all fields are @exports.
## `preview` is an optional static screenshot — EditorResourcePreviewGenerator
## can't help, since the showcase builds its content in _ready (which doesn't
## run during preview generation), so a thumbnail must be a captured image.

@export var tab_title: String = "Tab"
@export_file("*.tscn") var scene_path: String
@export_multiline var description: String
## Optional static screenshot shown above the Run button (no live preview is
## possible for a self-composing played scene — see the class doc).
@export var preview: Texture2D


func _ready() -> void:
	_build()


func get_tab_title() -> String:
	return tab_title


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
	heading.text = tab_title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override(&"font_size", 22)
	box.add_child(heading)

	if preview != null:
		var thumb := TextureRect.new()
		thumb.texture = preview
		thumb.custom_minimum_size = Vector2(360, 0)
		thumb.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(thumb)

	var desc := Label.new()
	desc.text = description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(440, 0)
	box.add_child(desc)

	var run := Button.new()
	run.text = "  ▶  Run showcase  "
	run.tooltip_text = "Play %s — a non-@tool gameplay scene; it runs the real systems on play, not in-editor." % scene_path
	run.size_flags_horizontal = SIZE_SHRINK_CENTER
	run.pressed.connect(_on_run_pressed)
	box.add_child(run)

	var hint := Label.new()
	hint.text = scene_path
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.5)
	box.add_child(hint)


func _on_run_pressed() -> void:
	if scene_path != "":
		EditorInterface.play_custom_scene(scene_path)
