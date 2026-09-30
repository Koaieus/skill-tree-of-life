class_name ExtractMode
extends ManageVerbMode

## Stays armed after a landed extract.

const _ICON := preload("res://assets/icons/addons/armed_extract.png")


func _init(p_ctl: PlayerInputController) -> void:
	ctl = p_ctl
	verb = PlayerInputController.ManageVerb.EXTRACT


func _command_for(entity_id: int, node_id: int) -> Command:
	return ExtractCommand.new(entity_id, node_id)


func _icon() -> Texture2D:
	return _ICON
