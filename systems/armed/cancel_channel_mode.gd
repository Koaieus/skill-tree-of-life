class_name CancelChannelMode
extends ManageVerbMode

## Cancel is a one-off, like Stake: a landed cancel pops the level; a denial
## keeps it armed for the retry. Icon and tint borrow Stake's until art and a
## palette key exist.

const _ICON := preload("res://assets/icons/addons/armed_stake.png")


func _init(p_ctl: PlayerInputController) -> void:
	ctl = p_ctl
	verb = PlayerInputController.ManageVerb.CANCEL


func _command_for(entity_id: int, node_id: int) -> Command:
	return CancelChannelCommand.new(entity_id, node_id)


func _icon() -> Texture2D:
	return _ICON


## The palette has no `cancel` key yet (it would read transparent).
func icon_tint() -> Color:
	return _PALETTE.color_for(&"stake")


func on_command_resolved(command: Command, success: bool) -> void:
	if success and command is CancelChannelCommand:
		pop_self()
