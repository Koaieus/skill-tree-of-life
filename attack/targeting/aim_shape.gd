@tool
@abstract
class_name AimShape
extends Resource

@export_range(0, 64, 1) var max_hits: int = 0


func crossed(_origin: Vector2, _angle: float, _length: float, _nodes: Array[SkillNode]) -> Array[SkillNode]:
	return []
