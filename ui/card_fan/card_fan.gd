@tool
class_name CardFan
extends Control

signal picked(scene: PackedScene)
signal hovered(scene: PackedScene)
signal dismissed
signal hub_pressed

@export var ring_radius_px: float = 110.0
@export var slot_step_deg: float = 34.0
@export var max_arc_deg: float = 200.0
@export var ring_gap_px: float = 8.0


static func slot_position(_i: int, _ring_radius: float, _step: float, _max_arc: float, _ring_gap: float) -> Vector2:
	return Vector2.ZERO


func bind(_entries: Array[PackedScene], _costs_of: Callable, _lit: Array[PackedScene]) -> void:
	pass


func cards() -> Array[TempUpgradeButton]:
	return []
