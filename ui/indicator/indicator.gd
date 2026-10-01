@tool
class_name Indicator
extends Node2D

## Base of the indicator family: a standalone world-space marker that wraps a
## thing of [member radius] (world px). Needs no parent, no [SkillNode] and no
## [HighlightController] — set [member radius], [member tint], [member tier]
## and it renders.
##
## Owns exactly ONE derived fact: [code]modulate = Emissive.at(tint,
## Emissive.stops(tier))[/code]. Draws nothing itself; members' children draw in
## white and inherit the modulate, so glow is a named tier, never a float
## (`.claude/rules/hdr-color.md`). Members push geometry INTO their children
## from [method _apply_geometry]; a child never reads the root.

@export var radius: float = 32.0:
	set(value):
		radius = value
		_apply_geometry()

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_update_modulate()

@export var tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		tier = value
		_update_modulate()

## Provider inputs, pushed by the overlay. Members read the ones they draw and
## ignore the rest. World direction to point along; ZERO = none.
@export var facing: Vector2 = Vector2.ZERO:
	set(value):
		facing = value
		_apply_geometry()

## Position in a sequence along the provider's shape; -1 = none.
@export var order: int = -1:
	set(value):
		order = value
		_apply_geometry()

## Fill fraction 0..1 (ranged: shots left / max shots); 1 = full.
@export_range(0.0, 1.0) var charge: float = 1.0:
	set(value):
		charge = clampf(value, 0.0, 1.0)
		_apply_geometry()

## Smallest on-screen stroke width any member draws at: [method stroke] widens
## a world-space width to [code]min_screen_px / zoom[/code] when the camera
## zooms out past it. Radii stay world-space. Zoom is this viewport's canvas
## transform scale (the level camera); a parent Node2D's scale is NOT
## compensated. Editor feedback: zoom the 2D viewport on target_reticle.tscn.
@export_range(0.0, 16.0, 0.1) var min_screen_px: float = 3.0:
	set(value):
		min_screen_px = value
		_apply_geometry()

# Canvas zoom the members' strokes were last sized for.
var _zoom: float = 1.0


func _ready() -> void:
	_zoom = _canvas_zoom()
	_update_modulate()
	_apply_geometry()


func _process(_delta: float) -> void:
	var z := _canvas_zoom()
	if z != _zoom:
		_zoom = z
		_apply_geometry()


func _canvas_zoom() -> float:
	if not is_inside_tree():
		return _zoom
	var z := get_viewport().get_canvas_transform().get_scale().x
	return z if z > 0.0 else _zoom


## A member's effective stroke width for world-space [param width]: never
## thinner than [member min_screen_px] on screen.
func stroke(width: float) -> float:
	return maxf(width, min_screen_px / _zoom)


func _update_modulate() -> void:
	modulate = Emissive.at(tint, Emissive.stops(tier))


## Member hook: push radius-relative geometry into the children. Called on
## every geometry setter and once at [method _ready]; must tolerate running
## before the children exist (setters fire during scene instantiation).
func _apply_geometry() -> void:
	pass
