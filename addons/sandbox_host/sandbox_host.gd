@tool
class_name SandboxHost
extends Control
## The full-screen tabbed host (#77 phase 1). A TabContainer that aggregates
## every module sandbox in one place:
##   • live-edit @tool panels — spell / VFX / stat-board (embedded, run live)
##   • played gameplay showcases — allocation / loot (launch cards)
##
## Tabs are registered explicitly (the table in _register_tabs). Each is a
## SandboxTab subclass declaring its mode; the host just adds it to the
## TabContainer. Inspector routing — push the selected resource into the
## matching live tab + reveal this screen — is driven by the EditorPlugin via
## route_to() / reveal_tab() / refresh().
##
## Scripts are instantiated via preload (not the global class_name) so the host
## composes cleanly even on the very first editor scan, before the class cache
## that backs `SandboxLiveTab`/`SandboxPlayedTab` typing exists.

const _LIVE_TAB := preload("res://addons/sandbox_host/sandbox_live_tab.gd")
const _PLAYED_TAB := preload("res://addons/sandbox_host/sandbox_played_tab.gd")

const _SPELL_PANEL := preload("res://addons/spell_playground/playground_panel.tscn")
const _VFX_PANEL := preload("res://addons/vfx_playground/playground_panel.tscn")
const _STATBOARD_PANEL := preload("res://addons/stat_board_visualizer/stat_board_graph.tscn")

var _tabs := TabContainer.new()
var _live_tabs: Dictionary = {}   # StringName id -> SandboxLiveTab


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tabs)
	_register_tabs()


func _register_tabs() -> void:
	# Live-edit panels — instance each playground's existing @tool scene.
	_add_live(&"spell", "Spell", _SPELL_PANEL, &"load_spell")
	_add_live(&"vfx", "VFX", _VFX_PANEL, &"load_coordinator")
	_add_live(&"statboard", "StatBoard", _STATBOARD_PANEL, &"load_board")
	# Played gameplay showcases — launch cards (can't run in-editor).
	_add_played("Allocation VFX", "res://scenes/dev/allocation_vfx_showcase.tscn",
		"Allocation / deallocation / death VFX on a 3×3 grid, driven by the real "
		+ "AllocationSystem + BattleSystem + VFX layers on a self-resetting loop.")
	_add_played("Loot", "res://scenes/dev/loot_showcase.tscn",
		"Kill → XP floater on the killer + a SkillDust relic blooming on the "
		+ "victim's former core, driven by the real LootSystem on a loop.")


func _add_live(id: StringName, title: String, panel_scene: PackedScene, loader: StringName) -> void:
	var tab := _LIVE_TAB.new()
	tab.name = title
	tab.setup(title, panel_scene.instantiate(), loader)
	_tabs.add_child(tab)
	_tabs.set_tab_title(tab.get_index(), title)
	_live_tabs[id] = tab


func _add_played(title: String, scene_path: String, description: String) -> void:
	var tab := _PLAYED_TAB.new()
	tab.name = title
	tab.setup(title, scene_path, description)
	_tabs.add_child(tab)
	_tabs.set_tab_title(tab.get_index(), title)


## Push a freshly-inspected resource into the named live tab (no screen switch).
func route_to(id: StringName, obj: Object) -> void:
	var tab: Variant = _live_tabs.get(id)
	if tab != null:
		tab.load_object(obj)


## Select the named tab (the EditorPlugin switches the main screen first).
func reveal_tab(id: StringName) -> void:
	var tab: Variant = _live_tabs.get(id)
	if tab != null:
		_tabs.current_tab = tab.get_index()


## Fire a no-arg panel method on a live tab (spell's live-edit refresh).
func refresh(id: StringName, method: StringName) -> void:
	var tab: Variant = _live_tabs.get(id)
	if tab != null:
		tab.call_panel(method)
