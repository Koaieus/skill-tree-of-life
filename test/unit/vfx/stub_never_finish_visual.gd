@tool
class_name StubNeverFinishVisual
extends Node2D

## Test stub: implements the [Projectile] visual contract but its
## [signal finished] is never emitted. The host [Projectile] hangs in its
## post-arrival `_wait_for_visual_done` forever, which is the point —
## tests use this to verify that a slow / hung visual does NOT delay the
## coordinator's wave clock.

signal finished


func _on_launch() -> void:
	pass


func _on_progress(_t: float) -> void:
	pass


func _on_arrival() -> void:
	pass
