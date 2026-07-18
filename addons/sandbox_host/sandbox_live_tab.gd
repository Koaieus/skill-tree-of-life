@tool
class_name SandboxLiveTab
extends SandboxTab
## A LIVE_EDIT tab: embeds an existing @tool panel scene (the spell / VFX /
## stat-board playgrounds) so it runs live in the editor exactly as it did in
## its old bottom panel.
##
## Authored as an **inherited scene** of `sandbox_live_tab.tscn` (the base): the
## base carries the shared chrome — a thin back-ref toolbar (jump to the panel's
## source scene / its folder, force a reload) over a `%PanelHost` slot — so the
## tree is scenic and previewable, per scene-composition.md. Each concrete tab is
## a one-node inherited scene that only overrides the four exports below. The
## panel itself is injected via `panel_scene` (DI) and instanced into the host in
## _ready; the host pushes the inspected resource through `load_object`, which
## forwards to the panel's own loader method by name.
##
## Back-refs (the "why is my tweak surface not one click away" fix): the toolbar
## resolves the panel's source `.tscn` from `panel_scene.resource_path` and opens
## it / reveals its folder via `EditorInterface`, so tuning the embedded scene is
## always reachable from the running tab. Editor-only (guarded by
## `Engine.is_editor_hint()`).
##
## Backward-compatible: a legacy tab that is a bare `MarginContainer` + this
## script (no `%PanelHost` / toolbar children) still works — the panel falls back
## to being parented on `self`, just without the chrome, until it's migrated to
## an inherited scene.
##
## A panel that wants a hard reset (stuck cast state, leftover VFX children,
## a build-once guard that won't re-run) can emit its own `reload_requested`
## signal (#144); it's connected here and also driven by the toolbar's reload
## button. Reload discards the instance and re-instantiates `panel_scene` from
## scratch — the last object routed through `load_object` is re-delivered so the
## reload doesn't lose context.

@export var tab_title: String = "Tab"
## Host routing key — must match the id the EditorPlugin routes to
## (spell / vfx / statboard).
@export var tab_id: StringName
## The @tool panel scene to embed (e.g. the spell playground panel). Also the
## back-ref target — the toolbar opens this scene's source for tuning.
@export var panel_scene: PackedScene
## Panel method that loads the currently-inspected resource (load_spell / …).
@export var loader_method: StringName

## Chrome from the base scene (`sandbox_live_tab.tscn`). Absent on un-migrated
## legacy tabs — every use is null-guarded so those keep working.
@onready var _panel_host: Control = get_node_or_null(^"%PanelHost")
@onready var _title_label: Label = get_node_or_null(^"%TitleLabel")
@onready var _breadcrumb: HBoxContainer = get_node_or_null(^"%Breadcrumb")
@onready var _reload_button: Button = get_node_or_null(^"%ReloadButton")
## Optional left column (collapsed by default). A tab that wants a directory
## browser drops a `DirectoryCardList`-shaped node in here and flips it visible;
## `_wire_sidebar` self-connects its `selected_resource` to `load_object`.
@onready var _sidebar: Control = get_node_or_null(^"%Sidebar")

var _panel: Control
var _last_loaded_object: Object


func _ready() -> void:
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		add_theme_constant_override(side, 4)
	_wire_chrome()
	_mount_panel()
	_wire_sidebar()


## Wires the base scene's toolbar to the back-ref actions and labels it. No-ops
## on a legacy tab that has no chrome nodes.
func _wire_chrome() -> void:
	if _title_label != null:
		_title_label.text = tab_title
	_build_breadcrumb()
	if _reload_button != null:
		_reload_button.pressed.connect(_on_panel_reload_requested)


## Fills the toolbar breadcrumb with the panel scene's path as clickable
## segments: each folder reveals itself in the FileSystem dock, the trailing
## file opens the scene. Data-driven (segment count varies by path), so it's
## built in code into the scene-provided `%Breadcrumb` container. Editor-only.
func _build_breadcrumb() -> void:
	if _breadcrumb == null:
		return
	for child in _breadcrumb.get_children():
		child.queue_free()
	var path := panel_scene.resource_path if panel_scene != null else ""
	if path.is_empty():
		return
	# "res://ui/tooltip_fan/fan_trace_panel.tscn" -> ["ui", "tooltip_fan", "file"]
	var rel := path.trim_prefix("res://")
	var parts := rel.split("/", false)
	var accum := "res://"
	for i in parts.size():
		var part := parts[i]
		accum += part
		var is_file := i == parts.size() - 1
		var target := accum if is_file else accum + "/"
		if i > 0:
			var sep := Label.new()
			sep.text = "/"
			sep.add_theme_color_override(&"font_color", Color(0.5, 0.6, 0.68, 0.5))
			_breadcrumb.add_child(sep)
		var seg := LinkButton.new()
		seg.text = part
		seg.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		seg.tooltip_text = "Open %s" % target if is_file else "Reveal %s" % target
		seg.pressed.connect(_open_source.bind(target, is_file))
		_breadcrumb.add_child(seg)
		if not is_file:
			accum += "/"


## Back-ref jump: open the scene (file) or reveal the folder in the FileSystem
## dock. Guarded — `EditorInterface` only exists inside the editor.
func _open_source(target: String, is_file: bool) -> void:
	if not Engine.is_editor_hint():
		return
	if is_file:
		EditorInterface.open_scene_from_path(target)
	else:
		EditorInterface.get_file_system_dock().navigate_to_path(target)


## Adopt-or-instance (#254): if the tab authored a panel *scenically* under
## `%PanelHost` (so it previews non-empty in the editor), adopt that child;
## otherwise instance `panel_scene`. Adoption is only ever done in the dedicated
## `%PanelHost` slot — the legacy `self` fallback holds chrome children, so it
## always instances rather than mistaking the toolbar for the panel.
func _mount_panel() -> void:
	if _panel_host != null:
		_panel = _find_baked_panel(_panel_host)
		if _panel == null:
			_panel = _instance_panel(_panel_host)
	else:
		_panel = _instance_panel(self)
	_finish_panel_setup()


## The first Control child of the panel slot, authored at edit time. Null when the
## slot is empty (the common case today — no tab bakes its panel in yet).
func _find_baked_panel(host: Node) -> Control:
	for child in host.get_children():
		if child is Control:
			return child
	return null


func _instance_panel(host: Node) -> Control:
	if panel_scene == null:
		return null
	var panel: Control = panel_scene.instantiate()
	host.add_child(panel)
	return panel


func _finish_panel_setup() -> void:
	if _panel == null:
		return
	_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	_panel.size_flags_vertical = SIZE_EXPAND_FILL
	if _panel.has_signal(&"reload_requested"):
		_panel.reload_requested.connect(_on_panel_reload_requested)
	if is_instance_valid(_last_loaded_object) and loader_method != &"" and _panel.has_method(loader_method):
		_panel.call(loader_method, _last_loaded_object)


## Self-wire a directory browser dropped into `%Sidebar`: any child exposing a
## `selected_resource` signal routes its selection through `load_object`. No-op
## when the sidebar is empty/collapsed (every shipped tab today).
func _wire_sidebar() -> void:
	if _sidebar == null:
		return
	for child in _sidebar.get_children():
		if child.has_signal(&"selected_resource"):
			child.selected_resource.connect(load_object)


## Discard the panel instance and rebuild it fresh from `panel_scene` — the only
## way to clear state a scene-recreate is meant to fix (see class doc). Reload
## always re-instances (never re-adopts): the authored child is gone after the
## first discard, and a fresh `panel_scene` copy is the whole point.
func _on_panel_reload_requested() -> void:
	if _panel == null:
		return
	var host := _panel.get_parent()
	var old := _panel
	_panel = null
	host.remove_child(old)
	old.queue_free()
	_panel = _instance_panel(host)
	_finish_panel_setup()


func get_tab_title() -> String:
	return tab_title


func get_mode() -> Mode:
	return Mode.LIVE_EDIT


## Forward a freshly-inspected resource into the embedded panel's loader.
func load_object(obj: Object) -> void:
	_last_loaded_object = obj
	if _panel != null and loader_method != &"" and _panel.has_method(loader_method):
		_panel.call(loader_method, obj)


## Fire a no-arg panel method (e.g. spell's `refresh_from_spell` on a live edit).
func call_panel(method: StringName) -> void:
	if _panel != null and _panel.has_method(method):
		_panel.call(method)
