@tool
class_name Cure
extends Resource

## STUB
@export var entries: Array[CureEntry] = []


func need_of(_node: SkillNode, _lctx: LandingContext) -> float:
	return 0.0


func plan(_node: SkillNode, _dose: float, _lctx: LandingContext) -> Dictionary:
	return {}
