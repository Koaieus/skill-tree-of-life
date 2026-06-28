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

@export var tab_title: String = "Tab"
## Host routing key — must match the id the EditorPlugin routes to
## (spell / vfx / statboard).
@export var tab_id: StringName
## The @tool panel scene to embed (e.g. the spell playground panel).
@export var panel_scene: PackedScene
## Panel method that loads the currently-inspected resource (load_spell / …).
@export var loader_method: StringName

var _panel: Control


func _ready() -> void:
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		add_theme_constant_override(side, 4)
	if panel_scene != null:
		_panel = panel_scene.instantiate()
		_panel.size_flags_horizontal = SIZE_EXPAND_FILL
		_panel.size_flags_vertical = SIZE_EXPAND_FILL
		add_child(_panel)


func get_tab_title() -> String:
	return tab_title


func get_mode() -> Mode:
	return Mode.LIVE_EDIT


## Forward a freshly-inspected resource into the embedded panel's loader.
func load_object(obj: Object) -> void:
	if _panel != null and loader_method != &"" and _panel.has_method(loader_method):
		_panel.call(loader_method, obj)


## Fire a no-arg panel method (e.g. spell's `refresh_from_spell` on a live edit).
func call_panel(method: StringName) -> void:
	if _panel != null and _panel.has_method(method):
		_panel.call(method)
