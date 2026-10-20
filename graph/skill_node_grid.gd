class_name SkillNodeGrid
extends RefCounted

const MAX_CELLS_PER_AXIS := 128

var max_radius: float = 0.0
var cols: int = 0
var rows: int = 0


func rebuild(_nodes: Array[SkillNode], _cell_px: float) -> void:
	pass


func note_radius(_r: float) -> void:
	pass


func candidates_within(_centre: Vector2, _reach: float) -> Array[SkillNode]:
	return [] as Array[SkillNode]


func is_empty() -> bool:
	return true
