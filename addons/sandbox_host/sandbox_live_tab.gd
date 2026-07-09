@tool
class_name SandboxLiveTab
extends SandboxTab
## A LIVE_EDIT tab: embeds an existing @tool panel scene (the spell / VFX /
## stat-board playgrounds) so it runs live in the editor exactly as it did in
## its old bottom panel.
##
## Authored as a scene in `addons/sandbox_host/tabs/`: the panel is injected via
## the `panel_scene` @export (DI, per scene-composition.md) and instanced in
## _ready, so the tab .tscn stays minimal (root + exports, no baked child). The
## host pushes the inspected resource through `load_object`, which forwards to
## the panel's own loader method by name.
##
## A panel that wants a hard reset (stuck cast state, leftover VFX children,
## a build-once guard that won't re-run) can emit its own `reload_requested`
## signal (#144) instead of trying to self-repair. If the panel declares one,
## it's connected here and handled by discarding the instance and
## re-instantiating `panel_scene` from scratch — the last object routed
## through `load_object` is re-delivered so the reload doesn't lose context.

@export var tab_title: String = "Tab"
## Host routing key — must match the id the EditorPlugin routes to
## (spell / vfx / statboard).
@export var tab_id: StringName
## The @tool panel scene to embed (e.g. the spell playground panel).
@export var panel_scene: PackedScene
## Panel method that loads the currently-inspected resource (load_spell / …).
@export var loader_method: StringName

var _panel: Control
var _last_loaded_object: Object


func _ready() -> void:
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		add_theme_constant_override(side, 4)
	_instantiate_panel()


func _instantiate_panel() -> void:
	if panel_scene == null:
		return
	_panel = panel_scene.instantiate()
	_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	_panel.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_panel)
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
	remove_child(old)
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
