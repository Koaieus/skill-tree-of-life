@tool
class_name CureEffect
extends SpellOnHitEffect

@export var cure: Cure = null
@export_range(0, 10, 0.1) var heal_per_stack: float = 1.0


func _apply_spell(_lctx: LandingContext) -> void:
	pass
