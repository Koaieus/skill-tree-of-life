@tool
class_name StatusOverlay
extends Control

## Stub — red phase.

class Segment:
	var id: StringName
	var rect: Rect2
	var color: Color

class IconEntry:
	var id: StringName
	var texture: Texture2D
	var count: int = -1
	var rect: Rect2

var segments: Array[Segment] = []
var icons: Array[IconEntry] = []


func bind(_host: Object, _changed: Signal) -> void:
	pass


func set_fill(_value: float, _max: float) -> void:
	pass


func refresh() -> void:
	pass
