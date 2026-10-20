@tool
class_name RetractSpread
extends PropagationSpread

@export var depth: int = 3


func select(_eligible: Array[SkillNode], _lctx: LandingContext) -> Array[PropagationPick]:
	return []
