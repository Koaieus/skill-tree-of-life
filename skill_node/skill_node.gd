@tool
class_name SkillNode
extends Area2D

signal radius_changed
signal owner_changed

# `owned_by` is the single source of truth for allocation:
# null  → unallocated
# !null → allocated
@export var owned_by: Entity = null:
	set(value):
		if owned_by == value:
			return
		owned_by = value
		owner_changed.emit()

@export var radius: float = 32.0:
	set(value):
		if is_equal_approx(radius, value):
			return
		radius = value
		radius_changed.emit()
		_sync_collision()

@onready var hover_ring: Node2D = $Visuals/HoverRing


func _ready() -> void:
	_sync_collision()


func _sync_collision() -> void:
	var collision := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	var shape := collision.shape as CircleShape2D
	if shape == null:
		return
	shape.radius = radius


func is_allocated() -> bool:
	return owned_by != null


func get_owner_color() -> Color:
	if owned_by:
		return owned_by.color
	return Color.WHITE


func _on_mouse_entered() -> void:
	hover_ring.show()


func _on_mouse_exited() -> void:
	hover_ring.hide()
