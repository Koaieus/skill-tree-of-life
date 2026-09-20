class_name StakeCommandHandler
extends NodeCommandHandler

## [StakeCommand] -> [method AllocationSystem.stake], gated by
## [method AllocationSystem.can_stake].


func _validate_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.can_stake(node, actor)


func _apply_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.stake(node, actor)
