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
##
## **Tabs build lazily.** The plugin mounts this host on editor launch and most
## sessions never open it, so `_ready` adds one empty placeholder per file,
## titled off a textual read of the scene (`read_tab_meta`, no `load()`: loading
## alone pulls the panel's whole dependency tree). A tab is instantiated only
## once the host is visible AND it is selected, and building one evicts any
## other — at most one tab is live, and the host stops processing while hidden.
## A route to an unbuilt tab is stashed and delivered when it builds.

const TABS_DIR := "res://addons/sandbox_host/tabs/"
const _PATH_META := &"sandbox_tab_path"

@onready var _tabs: TabContainer = $Tabs

var _live_tabs: Dictionary = {}   # StringName tab_id -> built SandboxLiveTab
var _tab_ids: Dictionary = {}     # StringName tab_id -> scene path (built or not)
var _pending: Dictionary = {}     # StringName tab_id -> Object to deliver on build
## Set across a child swap: removing the current child makes the TabContainer
## re-select (and emit `tab_changed`), which must not build a neighbour.
var _swapping := false


func _ready() -> void:
	_register_tabs()
	_tabs.tab_changed.connect(func(_idx: int) -> void: _build_current())
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _register_tabs() -> void:
	for file in _tab_scene_files():
		var path := TABS_DIR + file
		var meta := read_tab_meta(path)
		var placeholder := Control.new()
		placeholder.name = file.get_basename()
		placeholder.set_meta(_PATH_META, path)
		_tabs.add_child(placeholder)
		_tabs.set_tab_title(placeholder.get_index(), meta.get(&"title", file.get_basename()))
		if meta.has(&"id"):
			_tab_ids[meta[&"id"]] = path


## A tab scene's `tab_title` / `tab_id`, read off its root `[node]` block as
## text. Keys are absent when the root doesn't set them.
static func read_tab_meta(path: String) -> Dictionary:
	var out := {}
	var in_root := false
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("["):
			if in_root:
				break
			in_root = line.begins_with("[node ")
			continue
		if not in_root:
			continue
		if line.begins_with("tab_title = "):
			out[&"title"] = str_to_var(line.trim_prefix("tab_title = "))
		elif line.begins_with("tab_id = "):
			out[&"id"] = StringName(str_to_var(line.trim_prefix("tab_id = ")))
	return out


func _on_visibility_changed() -> void:
	var shown := is_visible_in_tree()
	process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED
	if shown:
		_build_current()


func _build_current() -> void:
	if _swapping or not is_visible_in_tree() or _tabs.current_tab < 0:
		return
	var current := _tabs.get_current_tab_control()
	if current == null or current is SandboxTab:
		return
	for child in _tabs.get_children():
		if child is SandboxTab:
			_evict(child)
	var tab := _swap_in(current, current.get_meta(_PATH_META))
	var id: Variant = tab.get(&"tab_id") if tab != null else null
	if id != null and _pending.has(id):
		tab.load_object(_pending[id])
		_pending.erase(id)


## Swap a built tab back to a placeholder, stashing what it had loaded.
func _evict(tab: SandboxTab) -> void:
	var id: Variant = tab.get(&"tab_id")
	if id != null and id != &"" and tab.has_method(&"get_last_loaded_object"):
		var carried: Object = tab.call(&"get_last_loaded_object")
		if is_instance_valid(carried):
			_pending[id] = carried
	var placeholder := Control.new()
	placeholder.name = tab.name
	placeholder.set_meta(_PATH_META, tab.scene_file_path)
	var idx := tab.get_index()
	var title := _tabs.get_tab_title(idx)
	if id != null:
		_live_tabs.erase(id)
	_swapping = true
	_tabs.remove_child(tab)
	tab.queue_free()
	_tabs.add_child(placeholder)
	_tabs.move_child(placeholder, idx)
	_tabs.set_tab_title(idx, title)
	_swapping = false


## Replace `old` (a placeholder or a built tab) with a fresh instance of `path`,
## in place; returns the new tab, or null (and leaves `old`) on failure.
func _swap_in(old: Node, path: String) -> SandboxTab:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("SandboxHost: could not load tab scene %s" % path)
		return null
	var fresh := scene.instantiate()
	if not (fresh is SandboxTab):
		push_warning("SandboxHost: %s root is not a SandboxTab" % path)
		fresh.queue_free()
		return null

	var idx := old.get_index()
	var was_current := _tabs.current_tab == idx
	# `tab_id` lives on SandboxLiveTab, not the base — reach it untyped, so a
	# PLAYED tab doesn't trip over it.
	var old_id: Variant = old.get(&"tab_id")
	if old_id != null and old_id != &"":
		_live_tabs.erase(old_id)
	_swapping = true
	_tabs.remove_child(old)
	old.queue_free()

	_tabs.add_child(fresh)
	_tabs.move_child(fresh, idx)
	_tabs.set_tab_title(idx, fresh.get_tab_title())
	var new_id: Variant = fresh.get(&"tab_id")
	if fresh.get_mode() == SandboxTab.Mode.LIVE_EDIT and new_id != null and new_id != &"":
		_live_tabs[new_id] = fresh
	if was_current:
		_tabs.current_tab = idx
	_swapping = false
	return fresh


## Rebuild one tab from its own `.tscn`, in place.
##
## Every tab instances its panel inside its own scene (the `%PanelHost` baked
## pattern, #437/#881), so there is nothing to re-instance: the panel is a
## child of the tab's scene, and the tab is what reloads.
##
## Scenic composition is not a style preference here. A panel that enters the tree
## as part of its scene and one that is `add_child`ed afterwards are not
## equivalent — the second is what kept the Bloom tab from ever running its glow
## pass (#371). Rebuilding from the scene file keeps reload on the same path as a
## cold open, so the two can't drift.
func reload_tab(tab: SandboxTab) -> void:
	var path := tab.scene_file_path
	if path.is_empty():
		push_warning("SandboxHost: %s has no scene file to reload from" % tab.name)
		return
	var carried: Object = null
	if tab.has_method(&"get_last_loaded_object"):
		carried = tab.call(&"get_last_loaded_object")
	var fresh := _swap_in(tab, path)
	if fresh != null and is_instance_valid(carried) and fresh.has_method(&"load_object"):
		fresh.load_object(carried)


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


## Push a freshly-inspected resource into the named live tab (no screen
## switch); an unbuilt tab gets it when it builds.
func route_to(id: StringName, obj: Object) -> void:
	var tab: Variant = _live_tabs.get(id)
	if tab != null:
		tab.load_object(obj)
	elif _tab_ids.has(id):
		_pending[id] = obj


## Select the named tab (the EditorPlugin switches the main screen first); it
## builds once the host is visible.
func reveal_tab(id: StringName) -> void:
	var tab: Variant = _live_tabs.get(id)
	if tab != null:
		_tabs.current_tab = tab.get_index()
		return
	var path: Variant = _tab_ids.get(id)
	if path == null:
		return
	for child in _tabs.get_children():
		if child.get_meta(_PATH_META, "") == path:
			_tabs.current_tab = child.get_index()
			_build_current()
			return


## Fire a no-arg panel method on a live tab (spell's live-edit refresh). An
## unbuilt tab has nothing to refresh — it reads fresh state when it builds.
func refresh(id: StringName, method: StringName) -> void:
	var tab: Variant = _live_tabs.get(id)
	if tab != null:
		tab.call_panel(method)
