class_name TempQuickbar
extends RefCounted

signal changed

var slots: Array[PackedScene] = []
var pinned: Array[bool] = []
var autofilled := false


func autofill(_placeable_in_order: Array[PackedScene]) -> void:
	pass


func on_aspect_gained(_kinds_of_that_aspect: Array[PackedScene]) -> void:
	pass


func swap(_i: int, _scene: PackedScene) -> void:
	pass


func scene_at(_i: int) -> PackedScene:
	return null
