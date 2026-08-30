@tool
class_name StubContextVisual
extends Node2D

## Test stub for #543 D6: records the [ScheduleEntry] the host [Projectile]
## forwards through the duck-typed `_on_context` hook, and the ORDER the hooks
## fired in.
##
## The order matters as much as the delivery. A visual that sizes or tints
## itself from its place in the cast must have the context before its first
## frame, so `_on_context` is expected to arrive BEFORE `_on_launch` — not one
## hook later, with a visible pop.

signal finished

var context: ScheduleEntry = null
var hooks: Array[StringName] = []


func _on_context(entry: ScheduleEntry) -> void:
	context = entry
	hooks.append(&"context")


func _on_launch() -> void:
	hooks.append(&"launch")


func _on_progress(_t: float) -> void:
	pass


func _on_arrival() -> void:
	hooks.append(&"arrival")
	finished.emit()
