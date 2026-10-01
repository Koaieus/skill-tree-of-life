@tool
class_name Indicator
extends Node2D

## Base of the indicator family: a standalone world-space marker that wraps a
## thing of [member radius] (world px). Needs no parent, no [SkillNode] and no
## [HighlightController] — set [member radius], [member tint], [member tier]
## and it renders.
##
## Owns exactly ONE derived fact: [code]modulate = Emissive.at(tint,
## Emissive.stops(tier))[/code]. Draws nothing itself; members' children draw in
## white and inherit the modulate, so glow is a named tier, never a float
## (`.claude/rules/hdr-color.md`). Members push geometry INTO their children
## from [method _apply_geometry]; a child never reads the root.

@export var radius: float = 32.0:
	set(value):
		radius = value
		_apply_geometry()

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_update_modulate()

@export var tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		tier = value
		_update_modulate()


func _ready() -> void:
	_update_modulate()
	_apply_geometry()


func _update_modulate() -> void:
	modulate = Emissive.at(tint, Emissive.stops(tier))


## Member hook: push radius-relative geometry into the children. Called on
## every geometry setter and once at [method _ready]; must tolerate running
## before the children exist (setters fire during scene instantiation).
func _apply_geometry() -> void:
	pass
