@tool
class_name AimedTargeting
extends Targeting

@export var shape: AimShape
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15") var ownership_filter: int = 8
@export var range_finder: EuclideanRangeFinder


func is_valid_target(_plan: AttackPlan, _source: SkillNode, _candidate: SkillNode) -> bool:
	return false


func seeds(_attacker: Entity, _source: SkillNode, _angle: float, _graph: Graph) -> Array[SkillNode]:
	return []
