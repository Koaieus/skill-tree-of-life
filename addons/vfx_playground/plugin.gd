## EditorPlugin: mounts a `PlaygroundPanel` in the bottom panel and an
## `EditorInspectorPlugin` that adds an "Open in VFX Playground" button
## whenever a [VFXCoordinator] is selected.
##
## Flow:
##   1. Inspector shows a VFXCoordinator → inspector plugin appends a Button.
##   2. User clicks → inspector plugin emits `playground_requested(coord)`.
##   3. This plugin loads the coord into the panel and reveals it.
##
## All authoring happens in the regular inspector — the panel is a preview
## harness with one Fire button and a read-only summary of current exports.
@tool
extends EditorPlugin

const _BOTTOM_PANEL_TITLE := "VFX Playground"
const _PANEL_SCENE := preload("res://addons/vfx_playground/playground_panel.tscn")

var _panel: Control
var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_panel = _PANEL_SCENE.instantiate()
	_panel.name = "VFXPlaygroundPanel"
	add_control_to_bottom_panel(_panel, _BOTTOM_PANEL_TITLE)

	_inspector = load("res://addons/vfx_playground/coordinator_inspector.gd").new()
	_inspector.playground_requested.connect(_on_playground_requested)
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
	if is_instance_valid(_inspector):
		remove_inspector_plugin(_inspector)


func _on_playground_requested(coord: VFXCoordinator) -> void:
	_panel.call(&"load_coordinator", coord)
	make_bottom_panel_item_visible(_panel)
