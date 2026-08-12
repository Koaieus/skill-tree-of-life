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
