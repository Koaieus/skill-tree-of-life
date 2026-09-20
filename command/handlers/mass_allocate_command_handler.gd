class_name MassAllocateCommandHandler
extends CommandHandler

## [MassAllocateCommand] -> [method AllocationSystem.mass_allocate].
## [member MassAllocateCommand.path_ids] carries the path ONLY — how much of it
## the actor can pay for is recomputed here, never taken from the sender, so a
## stale peer cannot dictate how much the authority spends (#458 decision).


## The same "can it pay for at least one hop" question [method _apply] asks,
## through the same one implementation.
func _validate(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var path := ctx.resolve_nodes((command as MassAllocateCommand).path_ids)
	return ctx.allocation_system.affordable_allocation_count(actor, path) >= 1


func _apply(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var path := ctx.resolve_nodes((command as MassAllocateCommand).path_ids)
	var affordable := ctx.allocation_system.affordable_allocation_count(actor, path)
	if affordable < 1:
		return false
	return ctx.allocation_system.mass_allocate(actor, path, affordable) > 0
