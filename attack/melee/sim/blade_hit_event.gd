class_name BladeHitEvent
extends RefCounted

## A single contact emitted by BladeHitScan. Either particle_idx or
## edge_idx is set; the other is -1.

var t: float = 0.0
var particle_idx: int = -1
var edge_idx: int = -1
var target: Object = null
## The contacting vertex's own speed (px/s) at this contact's sample step —
## the physics rate, not the sample rate (#779; see BladeState.speed_history).
## 0.0 for an edge hit: edges have no collision yet (#785) and nothing reads
## this field for one today; BladeHitScan never stamps it for an edge_idx
## event.
var speed: float = 0.0


func _init(
		t_: float = 0.0,
		particle_idx_: int = -1,
		edge_idx_: int = -1,
		target_: Object = null,
		speed_: float = 0.0) -> void:
	t = t_
	particle_idx = particle_idx_
	edge_idx = edge_idx_
	target = target_
	speed = speed_


func is_edge_hit() -> bool:
	return edge_idx >= 0
