@tool
class_name SkillNode
extends Area2D

signal radius_changed
signal owner_changed
signal clicked(skill_node: SkillNode)

# `owned_by` is the single source of truth for allocation:
# null  → unallocated
# !null → allocated
@export var owned_by: Entity = null:
	set(value):
		if owned_by == value:
			return
		owned_by = value
		owner_changed.emit()

## The modifier offerings this node carries — pushed onto an allocating
## entity's stat board by AllocationSystem. Node-level data, no behaviour.
@export var modifiers: Array[StatModifierDef] = []

@export var radius: float = 32.0:
	set(value):
		if is_equal_approx(radius, value):
			return
		radius = value
		radius_changed.emit()
		_sync_collision()

@onready var hover_ring: Node2D = $Visuals/HoverRing
@onready var core_marker: Node2D = $Visuals/CoreMarker

# Owner subscription tracking — re-bound whenever `owned_by` changes so the
# CoreMarker reflects the *current* owner's core_location, not a stale one.
var _bound_owner: Entity = null


func _ready() -> void:
	_sync_collision()
	owner_changed.connect(_refresh_core_marker)
	_refresh_core_marker()


func _refresh_core_marker() -> void:
	if _bound_owner != owned_by:
		if _bound_owner != null and _bound_owner.core_location_changed.is_connected(_refresh_core_marker):
			_bound_owner.core_location_changed.disconnect(_refresh_core_marker)
		_bound_owner = owned_by
		if _bound_owner != null:
			_bound_owner.core_location_changed.connect(_refresh_core_marker)
	core_marker.visible = owned_by != null and owned_by.core_location == self


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


func is_core() -> bool:
	return owned_by != null and owned_by.core_location == self


func get_owner_color() -> Color:
	if owned_by:
		return owned_by.color
	return Color.WHITE


func _on_mouse_entered() -> void:
	hover_ring.show()
	if not Engine.is_editor_hint():
		Events.skill_node_hovered.emit(self)


func _on_mouse_exited() -> void:
	hover_ring.hide()
	if not Engine.is_editor_hint():
		Events.skill_node_unhovered.emit()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(self)
