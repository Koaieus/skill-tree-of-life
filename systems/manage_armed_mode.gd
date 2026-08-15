class_name ManageArmedMode
extends ArmedMode

## A ManageBody tray card is armed (#338, #404) — Deallocate/Stake/Extract.
## ALLOCATE is deliberately excluded: arming it is cosmetic (cursor + card
## affordance only, per the acceptance spec — "the button is
## discoverable/tinted, the raw click is the accelerator"), and treating it
## as a poppable mode would regress right-click pin-toggle and gate the D key
## off for no functional reason the moment a player clicks the Allocate card,
## which is otherwise the idle default. Lowest priority in
## PlayerInputController._armed_modes: unlike TempUpgradeArmedMode (nests
## inside an attack plan), a Manage verb never coexists with an attack plan or
## core-move targeting (arm_manage_verb / enter_core_move_targeting enforce
## that mutual exclusion), so nesting order against those doesn't matter — it
## only needs to pop before falling through to pin-toggle / PauseMenu.

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	var v: PlayerInputController.ManageVerb = _ctl._manage_arm
	return v == PlayerInputController.ManageVerb.STAKE \
			or v == PlayerInputController.ManageVerb.EXTRACT \
			or v == PlayerInputController.ManageVerb.DEALLOCATE


func pop() -> bool:
	if not is_armed():
		return false
	_ctl._set_manage_arm(PlayerInputController.ManageVerb.NONE)
	return true
