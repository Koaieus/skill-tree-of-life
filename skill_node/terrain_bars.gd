@tool
class_name TerrainBars
extends Node2D

## STUB (#1796 red): the terrain bars south of the node.

class Layout:
	var frame_blocks: int = 0
	var inert_blocks: int = 0
	var fill_blocks: float = 0.0
	var overflow_blocks: int = 0


class Bar:
	var element: Element = null
	var count: int = 0
	var color: Color = Color.WHITE
	var label: String = ""
	var layout: Layout = null


var clock := TweenClock.new()


static func layout(_count: int, _degree: int, _k: int, _max_overflow: int) -> Layout:
	return Layout.new()


static func temperature_element(_t: int) -> Element:
	return null


static func shown_band(_element: Element, _band: ElementBand) -> ElementBand:
	return null


static func label_for(_node: SkillNode, _element: Element) -> String:
	return ""


static func bars_for(_node: SkillNode, _max_overflow: int) -> Array[Bar]:
	return []


func is_shown() -> bool:
	return false
