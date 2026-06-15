## EditorPlugin: mounts a `PlaygroundPanel` in the bottom panel and an
## `EditorInspectorPlugin` that adds an "Open in Spell Playground" button
## whenever a [SpellDef] is selected.
##
## Mirrors the layout of addons/vfx_playground/plugin.gd — same pattern,
## different domain (full spell resolution instead of just a coord preview).
@tool
extends EditorPlugin

const _BOTTOM_PANEL_TITLE := "Spell Playground"
const _PANEL_SCENE := preload("res://addons/spell_playground/playground_panel.tscn")

var _panel: Control
var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_panel = _PANEL_SCENE.instantiate()
	_panel.name = "SpellPlaygroundPanel"
	add_control_to_bottom_panel(_panel, _BOTTOM_PANEL_TITLE)

	_inspector = load("res://addons/spell_playground/spell_def_inspector.gd").new()
	_inspector.playground_requested.connect(_on_playground_requested)
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
	if is_instance_valid(_inspector):
		remove_inspector_plugin(_inspector)


func _on_playground_requested(spell: SpellDef) -> void:
	_panel.call(&"load_spell", spell)
	make_bottom_panel_item_visible(_panel)
