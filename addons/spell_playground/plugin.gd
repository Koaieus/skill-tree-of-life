## EditorPlugin: mounts a `PlaygroundPanel` in the bottom panel and an
## `EditorInspectorPlugin` that auto-syncs the panel with whichever [SpellDef]
## is currently inspected. The inspector button just reveals/focuses the
## panel — no manual load step.
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
	_inspector.spell_inspected.connect(_on_spell_inspected)
	_inspector.reveal_panel_requested.connect(_on_reveal_requested)
	add_inspector_plugin(_inspector)

	# Live property edits in the inspector don't always re-fire _parse_begin,
	# so subscribe to property_edited too and refresh the readout on edits.
	var insp := EditorInterface.get_inspector()
	if insp != null and not insp.property_edited.is_connected(_on_property_edited):
		insp.property_edited.connect(_on_property_edited)


func _exit_tree() -> void:
	var insp := EditorInterface.get_inspector()
	if insp != null and insp.property_edited.is_connected(_on_property_edited):
		insp.property_edited.disconnect(_on_property_edited)
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
	if is_instance_valid(_inspector):
		remove_inspector_plugin(_inspector)


func _on_spell_inspected(spell: SpellDef) -> void:
	if is_instance_valid(_panel):
		_panel.call(&"load_spell", spell)


func _on_reveal_requested() -> void:
	if is_instance_valid(_panel):
		make_bottom_panel_item_visible(_panel)


func _on_property_edited(_property: String) -> void:
	if is_instance_valid(_panel):
		_panel.call(&"refresh_from_spell")
