@tool
class_name BladeNode
extends Node2D

## Pure visual — its position is written each playback frame by SkillBlade
## from a BladeTrajectory sample. No physics, no collision.

const DEFAULT_STYLE: BladeStyle = preload("res://attack/melee/default_blade_style.tres")

@export_range(1.0, 100., 1.0) var radius: float = 32.0:
	set(value):
		radius = value
		_reconfigure()

@export var is_pivot: bool = false:
	set(value):
		is_pivot = value
		_reconfigure()

## Look profile (#256). Falls back to [constant DEFAULT_STYLE] so a bare
## `blade_node.tscn` still draws.
@export var style: BladeStyle = null:
	set(value):
		if style != null and style.changed.is_connected(_reconfigure):
			style.changed.disconnect(_reconfigure)
		style = value
		if style != null:
			style.changed.connect(_reconfigure)
		_reconfigure()

## The wielder's identity colour, blended in per [member BladeStyle.entity_tint].
## Transparent means "no owner" — the authored base is used as-is.
@export var tint: Color = Color.TRANSPARENT:
	set(value):
		tint = value
		_reconfigure()

## Interim pop state (#256): this vertex is dead, so it reads de-lit (HDR → SDR)
## instead of disappearing. Driven by [member SkillBlade.pop_result] during a
## live swing; also settable by hand for look tuning.
@export var disabled: bool = false:
	set(value):
		if disabled == value:
			return
		disabled = value
		_reconfigure()

@onready var _visual: Node2D = $Visuals/BladeCircle


func _ready() -> void:
	_reconfigure()


func _reconfigure() -> void:
	if not is_node_ready():
		return
	_visual.configure(radius, is_pivot, style if style != null else DEFAULT_STYLE, tint, disabled)


## Returns the point on this node's circumference facing `world_target`.
## BladeEdge uses this to trim edges to the rim.
func edge_point(world_target: Vector2) -> Vector2:
	var dir := (world_target - global_position).normalized()
	return global_position + dir * radius


func _to_string() -> String:
	return "<BladeNode>"
