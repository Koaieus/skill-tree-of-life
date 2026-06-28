class_name FloatingNumberLayer
extends Node2D

## Pure renderer: turns a [FloaterRequest] into a drifting, fading world-space
## number. Knows NOTHING about domain events, stats, entities, or fog — the
## [FloaterDirector] translates domain facts into requests and hands them here.
##
## Lives as a child of the FloaterDirector (Node2D under Graph/), sharing the
## graph's world coordinates — NOT on a CanvasLayer (that would detach floaters
## from Camera2D and break the world-anchored toaster). A high [member
## Node2D.z_index] orders floaters above graph content.

## The stock floater. A [FloaterStyle] may override it with an inherited scene.
const _FLOATER_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater.tscn")


## The single render chokepoint. Instantiate, stamp the style, anchor, animate.
## (Per-target toaster buffering — #79 — lands on top of this.)
func spawn(request: FloaterRequest) -> void:
	if request == null or request.text.is_empty():
		return
	var style := request.style
	var scene: PackedScene = _FLOATER_SCENE
	if style != null and style.scene_override != null:
		scene = style.scene_override
	var floater: Floater = scene.instantiate()
	floater.text = request.text
	if style != null:
		style.apply_to(floater)
	add_child(floater)
	floater.global_position = request.anchor_position()
	floater.animate()


## Convenience: spawn a plain number at [param target] with [param color] and
## otherwise-default styling, without composing a [FloaterRequest] by hand.
## Thin wrapper over [method spawn] — the predefined-variant escape hatch.
func spawn_simple(target: Node2D, text: String, color: Color) -> void:
	var style := FloaterStyle.new()
	style.fill_color = color
	var req := FloaterRequest.new()
	req.target = target
	req.text = text
	req.style = style
	spawn(req)
