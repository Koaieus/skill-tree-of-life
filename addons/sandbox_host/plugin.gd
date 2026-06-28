@tool
extends EditorPlugin
## Main-screen host for the unified module sandboxes (#77 phase 1).
##
## Replaces the three bottom-panel playground plugins (spell / VFX / stat-board)
## with one full-screen tabbed host (SandboxHost), and folds the played
## showcases in as launch cards. Reuses each playground's existing
## EditorInspectorPlugin verbatim, so the "Open in …" inspector buttons +
## auto-sync still work — they now reveal this main screen + select the matching
## tab instead of a bottom panel.
##
## Migration is reversible: the three old plugin folders are untouched; restoring
## them is a one-line flip of project.godot's [editor_plugins] enabled= array.

const _HOST_NAME := "Sandbox"
const _HOST_SCRIPT := preload("res://addons/sandbox_host/sandbox_host.gd")
const _SPELL_INSPECTOR := preload("res://addons/spell_playground/spell_def_inspector.gd")
const _VFX_INSPECTOR := preload("res://addons/vfx_playground/coordinator_inspector.gd")
const _STATBOARD_INSPECTOR := preload("res://addons/stat_board_visualizer/stat_board_inspector.gd")

var _host: Control
var _spell_inspector: EditorInspectorPlugin
var _vfx_inspector: EditorInspectorPlugin
var _statboard_inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_host = _HOST_SCRIPT.new()
	_host.name = _HOST_NAME
	_host.hide()
	EditorInterface.get_editor_main_screen().add_child(_host)

	# Spell: selecting a SpellDef passively syncs the tab; the inspector button
	# reveals the screen. Live property edits refresh the readout (as before).
	_spell_inspector = _SPELL_INSPECTOR.new()
	_spell_inspector.spell_inspected.connect(func(spell: Object) -> void: _route(&"spell", spell, false))
	_spell_inspector.reveal_panel_requested.connect(func() -> void: _reveal(&"spell"))
	add_inspector_plugin(_spell_inspector)
	var insp := EditorInterface.get_inspector()
	if insp != null and not insp.property_edited.is_connected(_on_property_edited):
		insp.property_edited.connect(_on_property_edited)

	# VFX + StatBoard: the inspector button both loads AND reveals.
	_vfx_inspector = _VFX_INSPECTOR.new()
	_vfx_inspector.playground_requested.connect(func(coord: Object) -> void: _route(&"vfx", coord, true))
	add_inspector_plugin(_vfx_inspector)

	_statboard_inspector = _STATBOARD_INSPECTOR.new()
	_statboard_inspector.visualize_requested.connect(func(board: Object) -> void: _route(&"statboard", board, true))
	add_inspector_plugin(_statboard_inspector)


func _exit_tree() -> void:
	var insp := EditorInterface.get_inspector()
	if insp != null and insp.property_edited.is_connected(_on_property_edited):
		insp.property_edited.disconnect(_on_property_edited)
	if _spell_inspector != null:
		remove_inspector_plugin(_spell_inspector)
	if _vfx_inspector != null:
		remove_inspector_plugin(_vfx_inspector)
	if _statboard_inspector != null:
		remove_inspector_plugin(_statboard_inspector)
	if is_instance_valid(_host):
		_host.queue_free()


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return _HOST_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Node", &"EditorIcons")


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_host):
		_host.visible = visible


## Push the inspected resource into its live tab. `reveal` also switches the
## main screen to us + selects the tab.
func _route(id: StringName, obj: Object, reveal: bool) -> void:
	if not is_instance_valid(_host):
		return
	_host.route_to(id, obj)
	if reveal:
		_reveal(id)


func _reveal(id: StringName) -> void:
	if not is_instance_valid(_host):
		return
	EditorInterface.set_main_screen_editor(_HOST_NAME)
	_host.reveal_tab(id)


func _on_property_edited(_property: String) -> void:
	if is_instance_valid(_host):
		_host.refresh(&"spell", &"refresh_from_spell")
