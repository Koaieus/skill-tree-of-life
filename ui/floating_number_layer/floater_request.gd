class_name FloaterRequest
extends RefCounted

## What the [FloaterDirector] hands the renderer: WHERE (a live world target, or
## a raw fallback position for escape-hatch one-offs), WHAT text, and HOW
## ([FloaterStyle]). Pure data — the renderer owns placement / toaster / lifetime.

## Live anchor. The toaster groups a burst by this node's instance id, and reads
## its [member Node2D.global_position] each spawn so a moving target keeps its stack.
var target: Node2D = null
## Fallback world position used only when [member target] is null.
var anchor: Vector2 = Vector2.ZERO
var text: String = ""
var style: FloaterStyle = null


func anchor_position() -> Vector2:
	return target.global_position if is_instance_valid(target) else anchor


## Stack-grouping key for the toaster. 0 = ungrouped (raw-position one-offs).
func stack_key() -> int:
	return target.get_instance_id() if is_instance_valid(target) else 0
