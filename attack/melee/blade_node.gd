@tool
class_name BladeNode
extends RigidBody2D

@export_range(1.0, 100., 1.0) var radius: float = 32.0:
	set(value):
		radius = value
		_sync_collision()
		if is_node_ready():
			_visual.configure(radius, is_pivot)

@export var is_pivot: bool = false:
	set(value):
		is_pivot = value
		if is_node_ready():
			_apply_pivot_freeze()
			_visual.configure(radius, is_pivot)

@onready var _visual: Node2D = $Visuals/BladeCircle
@onready var _col: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var _hitbox_col: CollisionShape2D = $Hitbox/HitboxShape

func _ready() -> void:
	_sync_collision()
	_apply_pivot_freeze()
	_visual.configure(radius, is_pivot)

func _sync_collision() -> void:
	if _col and _col.shape:
		(_col.shape as CircleShape2D).radius = radius
	if _hitbox_col and _hitbox_col.shape:
		(_hitbox_col.shape as CircleShape2D).radius = radius

func _apply_pivot_freeze() -> void:
	if is_pivot:
		freeze = true
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	else:
		freeze = false

## Returns the point on this node's circumference facing `world_target`.
## BladeEdge uses this instead of reimplementing the trim math.
func edge_point(world_target: Vector2) -> Vector2:
	var dir := (world_target - global_position).normalized()
	return global_position + dir * radius

func _to_string() -> String:
	return "<BladeNode>"
