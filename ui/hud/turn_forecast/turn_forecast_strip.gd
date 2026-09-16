class_name TurnForecastStrip
extends Control

## Stub seam for #910 — filled in once the tests are seen red.

@export var rest_count: int = 3
@export var hover_count: int = 8

var expanded: bool = false


func bind(_turn_manager: TurnManager, _vision_system: VisionSystem, _graph: Graph) -> void:
	pass


func set_player(_player: Entity) -> void:
	pass


func get_slot_entities() -> Array[Entity]:
	return []


func is_slot_highlighted(_index: int) -> bool:
	return false


func get_caption() -> String:
	return ""
