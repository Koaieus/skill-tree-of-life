@tool
class_name SandboxTooltipFanMount
extends Node
## Puts the real hover tooltip ([TooltipFan]) into a sandbox tab's world: drop
## one into the panel scene, call [method mount] once the world's [Graph]
## exists (again after a rebuild), and [method attach_motion] the container
## that hosts the world's SubViewport with the panel's own hit-test.
##
## The fan lives in a [CanvasLayer] inside the world's SubViewport: it anchors
## at the node's canvas-space position, so it must share the nodes' viewport
## but not their camera. It ignores the global hover Events (every tab's world
## shares them) and is driven only by this mount, with the `ui_more_info` gate
## held open — an editor tab has no Shift to read — and only [member
## pinned_units] allowed to fan out. See docs/domain/sandbox-framework-components.md.

## The [FanUnit]s (by node name in `fan.tscn`) this tab shows.
@export var pinned_units: Array[StringName] = [&"NodeStats", &"EffectReadout"]
## Hold the more-info gate open, so the units show on plain hover.
@export var force_more_info := true

const _FAN_SCENE := preload("res://ui/tooltip_fan/tooltip_fan.tscn")

## The live fan, or null before [method mount].
var fan: TooltipFan = null
var _layer: CanvasLayer = null
var _hovered: SkillNode = null


## (Re)builds the fan under [param world_canvas_parent] — any node inside the
## world's SubViewport — bound to [param graph]. A previous mount is retired.
func mount(world_canvas_parent: Node, graph: Graph) -> TooltipFan:
	_hovered = null
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = CanvasLayer.new()
	_layer.name = "TooltipFanLayer"
	fan = _FAN_SCENE.instantiate() as TooltipFan
	# Before `_ready`, which is where the fan would subscribe to Events.
	fan.listen_to_events = false
	fan.force_more_info = force_more_info
	fan.unit_filter = pinned_units
	_layer.add_child(fan)
	world_canvas_parent.add_child(_layer)
	fan.bind(graph)
	var viewport := _layer.get_viewport()
	fan.usable_rect_source = func() -> Rect2: return viewport.get_visible_rect()
	return fan


## Fans out around [param node]; null unhovers. The same node again is a no-op.
func hover(node: SkillNode) -> void:
	if node == null:
		unhover()
		return
	if node == _hovered or fan == null or not is_instance_valid(fan):
		return
	_hovered = node
	fan.show_for(node)


func unhover() -> void:
	if _hovered == null:
		return
	_hovered = null
	if fan != null and is_instance_valid(fan):
		fan.hide_fan()


## Hovers whatever [param pick] (`func(local_pos: Vector2) -> SkillNode`, null
## for empty space) returns under the pointer as it moves over [param
## container]; leaving the container unhovers.
func attach_motion(container: Control, pick: Callable) -> void:
	container.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hover(pick.call((event as InputEventMouseMotion).position) as SkillNode))
	container.mouse_exited.connect(unhover)
