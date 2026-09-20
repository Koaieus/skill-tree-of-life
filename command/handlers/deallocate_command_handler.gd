class_name DeallocateCommandHandler
extends NodeCommandHandler

## [DeallocateCommand] -> [method AllocationSystem.deallocate], gated by
## [method AllocationSystem.can_deallocate].


func _validate_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.can_deallocate(node, actor)


func _apply_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.deallocate(node, actor)
