@tool
class_name RingView
extends SubViewportContainer

signal cell_hovered(cell: StringName)
signal cell_clicked(cell: StringName)

enum State { LOCKED, BUYABLE, BOUGHT }


func show_state(_table: RingTable, _spent: Array[StringName], _selected: StringName) -> void:
	pass


func state_of(_cell: StringName) -> State:
	return State.LOCKED


func selected_cell() -> StringName:
	return &""


func display_graph() -> Graph:
	return null


func cell_local_position(_cell: StringName) -> Vector2:
	return Vector2.ZERO


func cell_at(_local: Vector2) -> StringName:
	return &""
