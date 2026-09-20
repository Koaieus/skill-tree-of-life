class_name StartTurnCommandHandler
extends CommandHandler

## [StartTurnCommand] -> [method TurnManager.start_turn], the run's opening
## cursor.


## The ONE thing this must not do is open a second cursor: every turn after the
## first is handed on by `_tick_until_ready` from inside
## [method TurnManager.end_turn], so a `start_turn` arriving mid-run would be a
## duplicate the mirror already has. `current_entity == null` is that guard, and
## it is also [method TurnManager.start_turn]'s own `assert` — which compiles
## out of a release build, so it cannot be the gate. See [StartTurnCommand].
func _validate(_command: Command, _actor: Entity, ctx: CommandContext) -> bool:
	return ctx.turn_manager != null and ctx.turn_manager.current_entity == null


func _apply(_command: Command, actor: Entity, ctx: CommandContext) -> bool:
	if ctx.turn_manager == null:
		return false
	# The initiative fill that [method GameRoot._ready] used to do inline,
	# moved here so it happens at the same point of the command stream on
	# every peer — the actor acts first because its clock is full, and a
	# mirror that filled its OWN hero's clock instead would tick to a
	# different entity on the very next [EndTurnCommand].
	if actor.stat_board != null and actor.stat_board.initiative != null:
		actor.stat_board.initiative.restore_to_full()
	ctx.turn_manager.start_turn(actor)
	return true
