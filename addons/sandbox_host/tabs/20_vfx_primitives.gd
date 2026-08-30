@tool
extends VBoxContainer

## The #670 primitive gallery — the left column of the VFX tab.
##
## The tab's main panel previews a whole [VFXCoordinator]; this previews the
## PIECES a coordinator is assembled from, which is what the eight per-spell
## units (#671-#678) actually shop for. Pick a body, a path, a pacing curve and
## a crit tier, hit Fire, watch it fly.
##
## Deliberately self-contained: its own [SubViewport] stage, its own origin and
## target, no reach into the coordinator panel next to it. The two halves of
## this tab share a tab and nothing else.
##
## Everything here is composed at runtime rather than authored as nodes because
## the control rows are DATA — one row per dropdown, and the dropdown contents
## are the catalogues below. Adding a sixth bolt config should be one line in
## [constant VISUALS], not a scene edit.

## Bodies, in the order the per-spell units meet them. Label → scene path.
const VISUALS: Array = [
	["Bolt · Small (Spark)", "res://ui/vfx/projectile/visual/bolt_small.tscn"],
	["Bolt · Blunt (Bruiser)", "res://ui/vfx/projectile/visual/bolt_blunt.tscn"],
	["Bolt · Streak (Leafblower)", "res://ui/vfx/projectile/visual/bolt_streak.tscn"],
	["Bolt · Packet (Resonator)", "res://ui/vfx/projectile/visual/bolt_packet.tscn"],
	["Bolt · Soft (Healing Beam)", "res://ui/vfx/projectile/visual/bolt_soft.tscn"],
	["Bolt · base", "res://ui/vfx/projectile/visual/bolt_body.tscn"],
	["ImpactRing · OUT", "res://ui/vfx/projectile/visual/impact_ring.tscn"],
	["ImpactRing · IN (absorb)", "res://ui/vfx/projectile/visual/impact_ring_absorb.tscn"],
	["EdgeEnergize", "res://ui/vfx/projectile/visual/edge_energize.tscn"],
]

## Paths, matching `.claude/rules/spell-vfx.md`'s catalogue. Label → script path.
const PATHS: Array = [
	["LinearPath", "res://ui/vfx/projectile/path/linear_path.gd"],
	["WavePath (P3)", "res://ui/vfx/projectile/path/wave_path.gd"],
	["JitterPath (P4)", "res://ui/vfx/projectile/path/jitter_path.gd"],
	["BezierArcPath", "res://ui/vfx/projectile/path/bezier_arc_path.gd"],
	["CubicBezierPath", "res://ui/vfx/projectile/path/cubic_bezier_path.gd"],
	["SelfLoopPath", "res://ui/vfx/projectile/path/self_loop_path.gd"],
]

const EASES: Array = ["Linear", "In", "Out", "In-Out", "Out-In"]

## The EdgeEnergize scene, which is previewed WITHOUT a [Projectile]: it is an
## overlay laid along an edge, not something thrown along one, so the stage
## drives its front directly. See `_fire_edge_energize`.
const EDGE_ENERGIZE_PATH := "res://ui/vfx/projectile/visual/edge_energize.tscn"

const _FLIGHT_SECONDS: float = 0.9
const _STAGE_MARGIN: float = 40.0

var _visual_picker: OptionButton
var _path_picker: OptionButton
var _ease_picker: OptionButton
var _crit_picker: OptionButton
var _stage: Node2D
var _viewport: SubViewport
var _origin_marker: Node2D
var _target_marker: Node2D


func _ready() -> void:
	custom_minimum_size = Vector2(240.0, 0.0)
	add_theme_constant_override(&"separation", 4)
	_build_header()
	_visual_picker = _build_picker("Body", VISUALS.map(func(e: Array) -> String: return e[0]))
	_path_picker = _build_picker("Path", PATHS.map(func(e: Array) -> String: return e[0]))
	_ease_picker = _build_picker("Ease", EASES)
	_crit_picker = _build_picker("Crit", ["none", "tier 1", "tier 2"])
	_build_fire_button()
	_build_stage()


func _build_header() -> void:
	var label := Label.new()
	label.text = "Primitives (#670)"
	label.add_theme_color_override(&"font_color", Color(0.6, 0.85, 0.95, 0.9))
	add_child(label)


func _build_picker(caption: String, entries: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(40.0, 0.0)
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = SIZE_EXPAND_FILL
	picker.clip_text = true
	for entry in entries:
		picker.add_item(str(entry))
	row.add_child(picker)
	return picker


func _build_fire_button() -> void:
	var button := Button.new()
	button.text = "▶  Fire"
	button.pressed.connect(_fire)
	add_child(button)


## A dark stage with an origin and a target marker, so a path's shape and a
## body's silhouette read against something rather than against nothing.
func _build_stage() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = SIZE_EXPAND_FILL
	container.size_flags_vertical = SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(0.0, 200.0)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.07)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(backdrop)

	_stage = Node2D.new()
	_viewport.add_child(_stage)
	_origin_marker = _build_marker(Color(0.45, 0.55, 0.65))
	_target_marker = _build_marker(Color(0.45, 0.55, 0.65))
	_viewport.size_changed.connect(_layout_stage)
	_layout_stage()


func _build_marker(colour: Color) -> Node2D:
	var marker := Node2D.new()
	var dot := ColorRect.new()
	dot.color = colour
	dot.size = Vector2(10.0, 10.0)
	dot.position = Vector2(-5.0, -5.0)
	marker.add_child(dot)
	_stage.add_child(marker)
	return marker


func _layout_stage() -> void:
	if _viewport == null:
		return
	var size := Vector2(_viewport.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_origin_marker.position = Vector2(_STAGE_MARGIN, size.y * 0.5)
	_target_marker.position = Vector2(size.x - _STAGE_MARGIN, size.y * 0.5)


func _clear_stage() -> void:
	for child in _stage.get_children():
		if child == _origin_marker or child == _target_marker:
			continue
		child.queue_free()


func _selected_visual_path() -> String:
	return VISUALS[maxi(0, _visual_picker.selected)][1]


func _fire() -> void:
	_clear_stage()
	var visual_path := _selected_visual_path()
	if visual_path == EDGE_ENERGIZE_PATH:
		_fire_edge_energize()
		return
	_fire_projectile(visual_path)


func _fire_projectile(visual_path: String) -> void:
	var projectile := Projectile.new()
	projectile.visual_scene = load(visual_path)
	projectile.path = _build_path()
	projectile.flight_time = _FLIGHT_SECONDS
	projectile.crit_tier = maxi(0, _crit_picker.selected)
	_stage.add_child(projectile)
	projectile.launch(_origin_marker.position, _target_marker.position)


## [EdgeEnergize] is an overlay laid ALONG an edge, not something thrown along
## one, so it gets no [Projectile]: the stage stamps its endpoints (the same
## stamp a coordinator does) and drives its front by hand.
func _fire_edge_energize() -> void:
	var overlay: Node2D = load(EDGE_ENERGIZE_PATH).instantiate()
	_stage.add_child(overlay)
	overlay.set(&"edge_origin", _origin_marker.position)
	overlay.set(&"edge_target", _target_marker.position)
	var tier: int = maxi(0, _crit_picker.selected)
	if tier > 0:
		overlay.call(&"_on_crit", tier)
	overlay.call(&"_on_launch")
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(overlay):
			overlay.call(&"_on_progress", t), 0.0, 1.0, _FLIGHT_SECONDS)
	tween.tween_callback(func() -> void:
		if is_instance_valid(overlay):
			overlay.call(&"_on_arrival"))


func _build_path() -> ProjectilePath:
	var script: GDScript = load(PATHS[maxi(0, _path_picker.selected)][1])
	var path: ProjectilePath = script.new()
	path.ease_curve = maxi(0, _ease_picker.selected) as ProjectilePath.Ease
	return path
