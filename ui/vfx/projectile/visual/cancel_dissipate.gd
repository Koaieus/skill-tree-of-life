@tool
class_name CancelDissipate
extends Node2D

## One-shot dissipate visual for [constant PropagationEvent.Verb.CANCEL] events.
## Spawned at the target node on the cancel beat; scales up + fades out,
## then emits [signal finished] so the coordinator knows it's safe to free.

signal finished

@export var color: Color = Color(1.0, 0.4, 0.4, 0.85)
@export var radius: float = 12.0
@export var expand_radius: float = 28.0
@export var duration: float = 0.35


func _ready() -> void:
	# In editor, show a preview at full opacity.
	if Engine.is_editor_hint():
		queue_redraw()
		return

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, ^"self_modulate:a", 0.0, duration)
	t.tween_property(self, ^"scale", Vector2(expand_radius / max(1.0, radius), expand_radius / max(1.0, radius)), duration).from(Vector2.ONE)
	# Redraw each frame so the circle grows smoothly.
	t.tween_callback(queue_redraw).set_delay(duration * 0.01)
	t.chain().tween_callback(func() -> void:
		finished.emit()
		queue_free())


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
