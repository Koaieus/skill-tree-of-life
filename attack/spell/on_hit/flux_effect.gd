@tool
class_name FluxEffect
extends SpellOnHitEffect

@export var def: StatusDef = null
@export_range(0, 1) var share: float = 0.5


func _apply_spell(_lctx: LandingContext) -> void:
	pass
