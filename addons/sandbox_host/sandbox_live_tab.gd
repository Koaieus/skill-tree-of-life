@tool
class_name SandboxLiveTab
extends SandboxTab
## A LIVE_EDIT tab: embeds an existing @tool panel Control (the spell / VFX /
## stat-board playgrounds) so it runs live in the editor exactly as it did in
## its old bottom panel. The panel keeps its own loader method; the host's
## inspector routing pushes the currently-inspected resource in via load_object,
## which forwards to that method by name.

var _title: String
var _panel: Control
var _loader_method: StringName


func setup(title: String, panel: Control, loader_method: StringName) -> void:
	_title = title
	_panel = panel
	_loader_method = loader_method
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		add_theme_constant_override(side, 4)
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(panel)


func get_tab_title() -> String:
	return _title


func get_mode() -> Mode:
	return Mode.LIVE_EDIT


## Forward a freshly-inspected resource into the embedded panel's loader.
func load_object(obj: Object) -> void:
	if _panel != null and _loader_method != &"" and _panel.has_method(_loader_method):
		_panel.call(_loader_method, obj)


## Fire a no-arg panel method (e.g. spell's `refresh_from_spell` on a live edit).
func call_panel(method: StringName) -> void:
	if _panel != null and _panel.has_method(method):
		_panel.call(method)
