class_name CancelChannelCommandHandler
extends NodeCommandHandler

## [CancelChannelCommand] -> [method AllocationSystem.cancel_channel], gated by
## [method AllocationSystem.can_cancel_channel].


func _validate_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.can_cancel_channel(node, actor)


func _apply_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.cancel_channel(node, actor)
