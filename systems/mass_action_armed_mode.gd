class_name MassActionArmedMode
extends ArmedMode

## A mass-allocate-path or mass-deallocate-cascade confirmation is pending
## (`PlayerInputController._mass_action_request` != null). Highest priority in
## `_armed_modes` — nothing should nest inside a pending confirmation.
##
## Live cancellation while the panel is up does NOT route through this —
## [MassActionConfirmPanel] freezes the input controller for as long as it is
## showing (`set_input_frozen`, #486), so PlayerInputController's own
## `_unhandled_input`/`_unhandled_key_input` (where `_pop_armed_mode` is
## called) bail out before reaching it. [ModalBase] owns Esc/right-click while
## a cancellable modal is up and calls `cancel_mass_action()` directly. This
## mode's `pop()` still matters for `_has_armed_mode()` correctness in headless
## tests that drive state with no modal in the tree at all.

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	return _ctl.pending_mass_action() != null


func pop() -> bool:
	if not is_armed():
		return false
	_ctl.cancel_mass_action()
	return true
