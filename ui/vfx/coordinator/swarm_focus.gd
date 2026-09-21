class_name SwarmFocus
extends Node2D
## The follow marker of a projectile coordinator: the damage-weighted centre of
## mass of its live [Projectile] siblings, projected onto the current wave's
## launch → landing segment so the camera travels toward the target and never
## bobs with the arc (#1042, ADR 0027). Holds position when nothing is live.

## Weight of a projectile whose hits carry no damage or heal amount, so a
## status-only bolt still pulls the camera a little rather than not at all.
const STATUS_FLOOR: float = 1.0

## Start a wave: the segment the COM's progress is measured along.
func begin_wave(_from: Vector2, _to: Vector2) -> void:
	pass


## The projected, clamped position for [param points] with [param weights]
## along the current segment — pure, so a test asserts it without a frame.
func project(_points: PackedVector2Array, _weights: PackedFloat32Array) -> Vector2:
	return global_position
