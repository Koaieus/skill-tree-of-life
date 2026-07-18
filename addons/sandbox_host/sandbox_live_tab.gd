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

var _panel: Control
var _last_loaded_object: Object


func _ready() -> void:
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		add_theme_constant_override(side, 4)
	_wire_chrome()
	_instantiate_panel()


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


func _instantiate_panel() -> void:
	if panel_scene == null:
		return
	_panel = panel_scene.instantiate()
	_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	_panel.size_flags_vertical = SIZE_EXPAND_FILL
	# Scenic tabs drop the panel into the base's %PanelHost (under the toolbar);
	# legacy bare-node tabs fall back to self.
	var host: Node = _panel_host if _panel_host != null else self
	host.add_child(_panel)
	if _panel.has_signal(&"reload_requested"):
		_panel.reload_requested.connect(_on_panel_reload_requested)
	if is_instance_valid(_last_loaded_object) and loader_method != &"" and _panel.has_method(loader_method):
		_panel.call(loader_method, _last_loaded_object)


## Discard the panel instance and rebuild it fresh from `panel_scene` — the
## only way to clear state a scene-recreate is meant to fix (see class doc).
func _on_panel_reload_requested() -> void:
	if _panel == null:
		return
	var old := _panel
	_panel = null
	old.get_parent().remove_child(old)
	old.queue_free()
	_instantiate_panel()


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
