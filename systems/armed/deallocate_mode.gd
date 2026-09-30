class_name DeallocateMode
extends ManageVerbMode

## Stays armed after a landed deallocate. A would-island refusal becomes a
## cascade offer — a [MassActionMode] pushed on top by the controller's
## feedback handler; cancelling it returns here.

const _ICON := preload("res://assets/icons/addons/armed_deallocate.png")


func _init(p_ctl: PlayerInputController) -> void:
	ctl = p_ctl
	verb = PlayerInputController.ManageVerb.DEALLOCATE


func _command_for(entity_id: int, node_id: int) -> Command:
	return DeallocateCommand.new(entity_id, node_id)


func _icon() -> Texture2D:
	return _ICON
