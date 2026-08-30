class_name CoreMoveArmedMode
extends ArmedMode

## Core-move targeting (#21) is active — the player's core is set as a
## click-to-move source (#404, generalized #406).

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	return _ctl._move_targeting_source != null


func pop() -> bool:
	if _ctl._move_targeting_source == null:
		return false
	_ctl._set_move_targeting_source(null)
	return true


## Badge art for core-move targeting (#664). Four outward arrows —
## `delapouite/move`. `delapouite/contract` was rejected for Extract precisely
## because its four INWARD arrows are the most confusable pair with this one at
## 24px; keeping this one unique is the other half of that decision.
const _ICON := preload("res://assets/icons/addons/armed_move_core.png")
const _PALETTE := preload("res://ui/theme/action_palette.tres")


func icon() -> Texture2D:
	return _ICON if is_armed() else null


## WIS gold, from the shared palette — the same value the Move Core tray card
## paints its title with, so the card the player just pressed and the badge now
## on their cursor match.
func icon_tint() -> Color:
	return _PALETTE.color_for(&"move_core") if is_armed() else Color.TRANSPARENT
