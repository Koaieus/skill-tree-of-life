class_name EndTurnCommandHandler
extends CommandHandler

## [EndTurnCommand] -> [method TurnManager.end_turn].


## No gate, deliberately: [method TurnManager.end_turn] has never had one and
## neither did the direct call it replaced (see
## [method PlayerInputController.request_end_turn]). Do not invent one.
func _validate(_command: Command, _actor: Entity, ctx: CommandContext) -> bool:
	return ctx.turn_manager != null


func _apply(_command: Command, _actor: Entity, ctx: CommandContext) -> bool:
	if ctx.turn_manager == null:
		return false
	ctx.turn_manager.end_turn()
	return true
