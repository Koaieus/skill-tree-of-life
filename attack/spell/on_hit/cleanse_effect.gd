@tool
class_name CleanseEffect
extends SpellOnHitEffect

@export var caps: Dictionary[StatusDef, int] = {}
@export var terms: Array[CleanseTerm] = []
@export var crit_when: LandingCondition = null
var template: CleanseEffect = null


func _apply_spell(_lctx: LandingContext) -> void:
	pass
