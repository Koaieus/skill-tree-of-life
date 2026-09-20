class_name ReloadCommandHandler
extends CommandHandler

## [ReloadCommand] -> [method Entity.reload].


## Actor's turn + 1 AP. The AP half is [method Entity.can_reload]'s own guard
## too — the same double-ask every mutating method keeps.
func _validate(_command: Command, actor: Entity, ctx: CommandContext) -> bool:
	return ctx.turn_manager != null and ctx.turn_manager.current_entity == actor \
			and actor.can_reload()


## A full quiver still pays the AP — the command was legal, it just minted
## nothing; returning true keeps the mirror's stream identical.
func _apply(_command: Command, actor: Entity, _ctx: CommandContext) -> bool:
	actor.reload()
	return true
