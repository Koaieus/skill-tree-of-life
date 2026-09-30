class_name StakeMode
extends ManageVerbMode

## Stake is a one-off (owner, 2026-09-30): a landed stake pops the level; a
## denial keeps it armed for the retry.

const _ICON := preload("res://assets/icons/addons/armed_stake.png")


func _init(p_ctl: PlayerInputController) -> void:
	ctl = p_ctl
	verb = PlayerInputController.ManageVerb.STAKE


func _command_for(entity_id: int, node_id: int) -> Command:
	return StakeCommand.new(entity_id, node_id)


func _icon() -> Texture2D:
	return _ICON


func on_command_resolved(command: Command, success: bool) -> void:
	if success and command is StakeCommand:
		pop_self()
