class_name NodeCommandHandler
extends CommandHandler

## The shared base for the verbs whose whole payload is one target node
## ([NodeCommand]): resolves [member NodeCommand.node_id] once and hands the
## live node to [method _validate_node] / [method _apply_node].


func _validate(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var node := ctx.resolve_node((command as NodeCommand).node_id)
	if node == null:
		push_warning("CommandApplier: no node for stable_id %d (%s)" \
				% [(command as NodeCommand).node_id, command.type_tag()])
		return false
	return _validate_node(command as NodeCommand, node, actor, ctx)


func _apply(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var node := ctx.resolve_node((command as NodeCommand).node_id)
	if node == null:
		return false
	return _apply_node(command as NodeCommand, node, actor, ctx)


func _validate_node(command: NodeCommand, _node: SkillNode, _actor: Entity,
		_ctx: CommandContext) -> bool:
	push_warning("CommandApplier: no validator for node command '%s'" % command.type_tag())
	return false


func _apply_node(command: NodeCommand, _node: SkillNode, _actor: Entity,
		_ctx: CommandContext) -> bool:
	push_warning("CommandApplier: no handler for node command '%s'" % command.type_tag())
	return false
