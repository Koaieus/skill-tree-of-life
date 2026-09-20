class_name LaunchAttackCommandHandler
extends CommandHandler

## [LaunchAttackCommand] -> [method BattleSystem.apply_launch_command].


## The one gate that PRODUCES as well as decides — see [CommandHandler]'s note.
## The attack's real gate is "resolve, then check affordability", and the
## resolution it needs is the command's own record; #545 moved both here from
## the apply so the record is final before the confirm.
func _validate(command: Command, _actor: Entity, ctx: CommandContext) -> bool:
	return ctx.battle_system != null \
			and ctx.battle_system.prepare_launch_command(command as LaunchAttackCommand)


func _apply(command: Command, _actor: Entity, ctx: CommandContext) -> bool:
	if ctx.battle_system == null:
		return false
	@warning_ignore("redundant_await")
	return await ctx.battle_system.apply_launch_command(command as LaunchAttackCommand)
