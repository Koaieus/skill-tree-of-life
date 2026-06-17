class_name BladeHitEvent
extends RefCounted

## A single contact emitted by BladeHitScan. Either particle_idx or
## edge_idx is set; the other is -1.

var t: float = 0.0
var particle_idx: int = -1
var edge_idx: int = -1
var target: Object = null


func _init(
		t_: float = 0.0,
		particle_idx_: int = -1,
		edge_idx_: int = -1,
		target_: Object = null) -> void:
	t = t_
	particle_idx = particle_idx_
	edge_idx = edge_idx_
	target = target_


func is_edge_hit() -> bool:
	return edge_idx >= 0
