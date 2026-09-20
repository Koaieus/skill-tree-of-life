class_name AllocateCommandHandler
extends NodeCommandHandler

## [AllocateCommand] -> [method AllocationSystem.allocate], gated by
## [method AllocationSystem.can_allocate].


func _validate_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.can_allocate(node, actor)


func _apply_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.allocate(node, actor)
