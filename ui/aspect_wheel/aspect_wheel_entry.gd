class_name AspectWheelEntry
extends RefCounted

## One wedge of an [AspectWheel]: an aspect the caller can offer, how much of
## it is held, and whether it may be picked. Pure data; the caller builds these.

## What [signal AspectWheel.picked] / [signal AspectWheel.hovered] report.
var id: StringName = &""
## Tint and badge source.
var identity: Identity = null
## Amount held; drives the wedge's fill radius.
var value: int = 0
## Already in another socket — drawn with a check, still pickable.
var checked: bool = false
## Why this entry cannot be picked; empty means pickable.
var disabled_reason: String = ""
## What the hub shows while this wedge is hovered.
var hub_text: String = ""


func _init(p_id: StringName = &"", p_identity: Identity = null, p_value: int = 0) -> void:
	id = p_id
	identity = p_identity
	value = p_value


func is_pickable() -> bool:
	return disabled_reason.is_empty()
