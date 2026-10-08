@tool
class_name ContentRanker
extends NodeRanker

@export var modifier_weight: float = 1.0
@export var grant_weight: float = 2.0
@export var addon_weight: float = 2.0


func score(_node: SkillNode, _lctx: LandingContext) -> float:
	return 0.0
