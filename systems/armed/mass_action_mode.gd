class_name MassActionMode
extends ArmedMode

## A pending multi-node confirmation ([MassActionRequest]), pushed on whatever
## is on top. The board is frozen while it is up: every click is consumed.
## Confirm and cancel pop it (see [method PlayerInputController.confirm_mass_action]).
##
## No badge and no tint: the confirm panel is its own, much louder, presentation.

var request: MassActionRequest


func _init(p_ctl: PlayerInputController, p_request: MassActionRequest) -> void:
	ctl = p_ctl
	request = p_request


func handle_left_click(_node: SkillNode) -> bool:
	return true
