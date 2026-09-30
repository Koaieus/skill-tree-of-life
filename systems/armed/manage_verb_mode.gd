class_name ManageVerbMode
extends ArmedMode

## A Manage verb level pushed on [ManageMode] — Stake, Extract, Deallocate.
## Its click submits the verb's command on any node, legal or not: a denial is
## feedback the controller shows, and the click is consumed either way.

const _PALETTE := preload("res://ui/theme/action_palette.tres")

var verb: PlayerInputController.ManageVerb


func handle_left_click(node: SkillNode) -> bool:
	ctl._submit(_command_for(ctl.player.entity_id, ctl.graph.get_stable_id(node)))
	return true


func _command_for(_entity_id: int, _node_id: int) -> Command:
	return null


func _icon() -> Texture2D:
	return null


func icon() -> Texture2D:
	return _icon()


func icon_tint() -> Color:
	return _PALETTE.color_for(StringName(
			PlayerInputController.ManageVerb.keys()[verb].to_lower()))
