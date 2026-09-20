class_name DeallocateSetCommandHandler
extends CommandHandler

## [DeallocateSetCommand] -> [method AllocationSystem.deallocate_set].


func _validate(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var nodes := ctx.resolve_nodes((command as DeallocateSetCommand).node_ids)
	return ctx.allocation_system.can_deallocate_set(nodes, actor)


func _apply(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var nodes := ctx.resolve_nodes((command as DeallocateSetCommand).node_ids)
	return ctx.allocation_system.deallocate_set(nodes, actor)
