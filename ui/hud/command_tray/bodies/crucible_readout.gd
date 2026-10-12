class_name CrucibleReadout
extends VBoxContainer

## Stub.

signal anchors_changed

@export var force_more_info := false


func bind(_plan: MagicAttackPlan) -> void:
	pass


func line_nodes() -> Array[CrucibleReadoutLine]:
	var out: Array[CrucibleReadoutLine] = []
	return out


func line_anchor(_socket: int) -> Vector2:
	return Vector2.INF


func set_hovered_socket(_socket: int) -> void:
	pass


func preview_wedge(_socket: int, _aspect_id: StringName) -> void:
	pass


func clear_preview() -> void:
	pass


func is_more_info() -> bool:
	return false


func name_text() -> String:
	return ""
