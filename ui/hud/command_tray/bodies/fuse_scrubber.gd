class_name FuseScrubber
extends HBoxContainer
## Stub — filled in after the red test.

signal edited
signal marker_hovered(gate: Gate, hovering: bool)

var plan: MeleeAttackPlan = null


func sync(_plan: MeleeAttackPlan) -> void:
	pass


func is_editing() -> bool:
	return false


func drag(_gate: Gate, _t: float, _split := false) -> void:
	pass


func relink() -> void:
	pass


func clear() -> void:
	pass


func show_stranded(_count: int) -> void:
	pass


func stranded_count() -> int:
	return 0
