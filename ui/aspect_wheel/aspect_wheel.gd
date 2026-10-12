@tool
class_name AspectWheel
extends Control

signal hovered(id: StringName)
signal picked(id: StringName)
signal dismissed

@export var radius_px: float = 96.0
@export var inner_radius_px: float = 28.0
@export var wedge_gap_deg: float = 3.0
@export var min_fill: float = 0.15

var _entries: Array[AspectWheelEntry] = []


func bind(entries: Array[AspectWheelEntry]) -> void:
	pass


func wedge_span(_index: int) -> Vector2:
	return Vector2.ZERO


func wedge_at(_local_pos: Vector2) -> StringName:
	return &""


func fill_radius(_index: int) -> float:
	return 0.0
