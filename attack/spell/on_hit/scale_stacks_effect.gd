@tool
class_name ScaleStacksEffect
extends SpellOnHitEffect

@export var when: LandingCondition = null
@export var ranker: NodeRanker = null
@export var factor: float = 1.0


func _apply_spell(_lctx: LandingContext) -> void:
	pass
