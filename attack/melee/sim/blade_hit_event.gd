class_name BladeHitEvent
extends RefCounted

## A single contact emitted by BladeHitScan. Either particle_idx or
## edge_idx is set; the other is -1.

var t: float = 0.0
var particle_idx: int = -1
var edge_idx: int = -1
var target: Object = null
## The contacting element's speed (px/s) at this contact's sample step — the
## physics rate, not the sample rate (#779; see BladeState.speed_history). For
## a vertex that is the vertex's own speed; for an EDGE (#785) it is the mean
## of its two endpoints', i.e. the segment midpoint's speed under rigid motion.
## See BladeHitScan._edge_speed_at for why the mean is what keeps a
## pivot-adjacent edge near-inert without a flag.
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
