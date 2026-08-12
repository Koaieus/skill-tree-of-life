class_name TempUpgradeArmedMode
extends ArmedMode

## Innermost armed-mode level (#406): a temp-upgrade card is armed, waiting
## for a click on a blade member to resolve. Sits ON TOP OF an already-armed
## attack plan, so it must pop before the plan does — checked first in
## PlayerInputController._armed_modes.

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	return _ctl._temp_upgrade_arm != null


func pop() -> bool:
	if _ctl._temp_upgrade_arm == null:
		return false
	_ctl._set_temp_upgrade_arm(null)
	return true
