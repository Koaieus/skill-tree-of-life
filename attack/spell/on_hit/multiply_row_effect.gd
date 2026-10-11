@tool
class_name MultiplyRowEffect
extends OnHitEffect

@export var def: StatusDef = null
@export_range(1.0, 5.0, 0.1) var factor: float = 2.0


func apply(_landing: HitLanding) -> void:
	pass
