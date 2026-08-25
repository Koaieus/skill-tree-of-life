@tool
class_name MenuNodePickRegion
extends Control

## The mouse hit area of one [MenuNodeView] (#583).
##
## [b]A [Control], not an [Area2D], and that is the load-bearing choice.[/b]
## [HoverPreview] enforces #571's "a peek-ahead is not clickable" by walking a
## view's [Control] descendants and forcing `mouse_filter` / `focus_mode`
## (`_capture_picking` / `_apply_picking`), restoring exactly what the scene
## authored. An [Area2D] is invisible to that walk, so a collapsed node would
## have stayed clickable through its own preview — a second picking rule to keep
## in sync with the first, which is the thing that unit exists to avoid.
##
## It also settles the ordering problem. GUI picking runs BEFORE physics
## picking, so a full-rect [Control] anywhere above the menu (`MetaRoot` is one)
## swallows the event and an [Area2D] never hears it. A [Control] hit area
## competes in the same pass as everything else that could shadow it.
##
## A [Control] under a [Node2D] under a [Camera2D] picks correctly: the engine
## tests `get_global_transform_with_canvas()`, which carries the camera and the
## view's own [member Node2D.scale] — so a collapsed node's hit area shrinks with
## it for free.

## Emitted on a left click inside the disk. Named for the intent, not the
## device, because #576's keyboard path commits through the same seam.
signal activated

## The disk's radius in the view's local units. Written by
## [method MenuNodeView._sync_radius]; the rect is kept square around the
## view's origin so the [Control] and the visual agree at any size.
@export_range(4.0, 128.0, 0.5) var radius: float = 32.0:
	set(value):
		radius = value
		_resize()


func _ready() -> void:
	_resize()


## Round hit test, so the corners between two adjacent nodes belong to neither.
## Without it a square hit area would let a click land on a node the cursor is
## visibly outside of, which reads as the menu picking the wrong item.
func _has_point(point: Vector2) -> bool:
	return point.distance_squared_to(size * 0.5) <= radius * radius


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	accept_event()
	activated.emit()


func _resize() -> void:
	size = Vector2.ONE * radius * 2.0
	position = -Vector2.ONE * radius
