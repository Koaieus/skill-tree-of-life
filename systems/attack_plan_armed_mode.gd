class_name AttackPlanArmedMode
extends ArmedMode

## An attack plan (melee/ranged/magic) is armed for this player (#404,
## generalized #406). Wraps the existing "pop the plan's own stack, or
## cancel the plan entirely if it has nothing left to pop" logic.

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	return _ctl.can_player_act() and _ctl._active_attack_plan() != null


func pop() -> bool:
	var plan := _ctl._active_attack_plan()
	if plan == null:
		return false
	if not plan.pop():
		_ctl.battle_system.cancel_attack()
	return true
