class_name SwarmFocus
extends Node2D
## The follow marker of a projectile coordinator: the damage-weighted centre of
## mass of its live [Projectile] siblings, projected onto the current wave's
## launch → landing segment so the camera travels toward the target and never
## bobs with the arc (ADR 0027). Holds position when nothing is live.
##
## Owner call (2026-09-21): *"camera should move directly towards the target,
## not also upward. But should still follow swarm COM insofar it moves towards
## target."* — hence the projection: the COM's PROGRESS along `from → to` is
## kept, its lift off the line is discarded.
##
## Sits as the coordinator's `%FocusMarker`; the coordinator answers
## [method VFXCoordinator.focus_marker] with it and calls [method begin_wave]
## once per wave. Polls its siblings every frame — a projectile is live while
## [method Projectile.is_in_flight] holds — and weighs each by
## [member Projectile.focus_weight].

## Weight of a projectile whose hits carry no damage or heal amount, so a
## status-only bolt still pulls the camera a little rather than not at all.
const STATUS_FLOOR: float = 1.0

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _wave_open: bool = false


## Start a wave: the segment the COM's progress is measured along. The marker
## snaps to [param from] — during a wind-up nothing is live, so this is where
## the camera holds until the first projectile moves.
func begin_wave(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	_wave_open = true
	global_position = from


## The projected, clamped position for [param points] with [param weights]
## along the current segment — pure, so a test asserts it without a frame.
## An empty [param points] answers the current position (hold). A weight at or
## below zero counts as [constant STATUS_FLOOR]; a missing weight likewise.
func project(points: PackedVector2Array, weights: PackedFloat32Array) -> Vector2:
	if points.is_empty():
		return global_position
	var total := 0.0
	var com := Vector2.ZERO
	for i in points.size():
		var w: float = weights[i] if i < weights.size() else 0.0
		if w <= 0.0:
			w = STATUS_FLOOR
		com += points[i] * w
		total += w
	com /= total
	var seg := _to - _from
	var len_sq := seg.length_squared()
	if len_sq <= 0.000001:
		return _from
	var s := clampf((com - _from).dot(seg) / len_sq, 0.0, 1.0)
	return _from + seg * s


func _process(_delta: float) -> void:
	if not _wave_open:
		return
	var parent := get_parent()
	if parent == null:
		return
	var points := PackedVector2Array()
	var weights := PackedFloat32Array()
	for child in parent.get_children():
		var proj := child as Projectile
		if proj == null or not proj.is_in_flight():
			continue
		points.append(proj.global_position)
		weights.append(proj.focus_weight)
	if points.is_empty():
		return
	global_position = project(points, weights)
