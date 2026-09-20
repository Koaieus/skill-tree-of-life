class_name ExtractCommandHandler
extends NodeCommandHandler

## [ExtractCommand] -> [method AllocationSystem.extract], gated by
## [method AllocationSystem.can_extract].


func _validate_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.can_extract(node, actor)


func _apply_node(_command: NodeCommand, node: SkillNode, actor: Entity,
		ctx: CommandContext) -> bool:
	return ctx.allocation_system.extract(node, actor)
