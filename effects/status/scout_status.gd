@tool
class_name ScoutStatus
extends StatusDef

@export var radius_scale: float = 0.5
@export var fallback_radius_factor: float = 10.0


func radius_for(_node: SkillNode, _stacks: int) -> float:
	return 0.0
