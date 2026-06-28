@tool
class_name SandboxHost
extends Control
## The full-screen tabbed host (#77). Aggregates every module sandbox in one
## TabContainer: the live-edit @tool panels (spell / VFX / stat-board, embedded)
## and the played gameplay showcases (allocation / loot, launch cards).
##
## Authored as `sandbox_host.tscn` (Control + a TabContainer child). Tabs are
## **auto-discovered**: every `*.tscn` under `tabs/` whose root is a SandboxTab
## is loaded and added, sorted by filename (numeric prefixes order them). Adding
## a tab = drop a scene in that folder; no code change. This supersedes the
## issue's original `get_global_class_list` plan — a dedicated directory is the
## declaration, so we never load scenes just to detect inheritance.
##
## Inspector routing — push the selected resource into the matching live tab +
## reveal this screen — is driven by the EditorPlugin via route_to() /
## reveal_tab() / refresh(), keyed on each live tab's `tab_id`.

const TABS_DIR := "res://addons/sandbox_host/tabs/"

@onready var _tabs: TabContainer = $Tabs

var _live_tabs: Dictionary = {}   # StringName tab_id -> SandboxLiveTab


func _ready() -> void:
	_register_tabs()


func _register_tabs() -> void:
	for file in _tab_scene_files():
		var scene: PackedScene = load(TABS_DIR + file)
		if scene == null:
			push_warning("SandboxHost: could not load tab scene %s" % file)
			continue
		var tab := scene.instantiate()
		if not (tab is SandboxTab):
			push_warning("SandboxHost: %s root is not a SandboxTab; skipping" % file)
			tab.queue_free()
			continue
		_tabs.add_child(tab)
		_tabs.set_tab_title(tab.get_index(), tab.get_tab_title())
		if tab.get_mode() == SandboxTab.Mode.LIVE_EDIT and tab.tab_id != &"":
			_live_tabs[tab.tab_id] = tab


## Sorted list of tab scene filenames (numeric prefixes give a stable order).
func _tab_scene_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TABS_DIR)
	if dir == null:
		push_warning("SandboxHost: tabs dir missing: %s" % TABS_DIR)
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			out.append(f)
	out.sort()
	return out


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
