class_name EntityState
extends RefCounted

## STUB (#1143 red).
var stat_board: EntityStatBoard = null
var tags: Dictionary[StringName, int] = {}
var core_location: SkillNode = null
var effect_instances: Array[EffectInstance] = []


func clone() -> EntityState:
	return EntityState.new()
