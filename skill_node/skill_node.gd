@tool
class_name SkillNode
extends Area2D

signal radius_changed
signal allocation_state_changed

enum AllocationState {
	UNALLOCATED,
	ALLOCATED,
	LOCKED,
}

@export var radius: float = 32.0:
	set(value):
		if is_equal_approx(radius, value):
			return
		radius = value
		radius_changed.emit()
		_sync_collision()

@export var allocation_state: AllocationState = AllocationState.UNALLOCATED:
	set(value):
		if allocation_state == value:
			return
		allocation_state = value
		allocation_state_changed.emit()


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
