class_name MoveCoreCommandHandler
extends CommandHandler

## [MoveCoreCommand] -> [method AllocationSystem.move_core], one hop at a time.

## Beat between hops, so a multi-hop walk reads as a cascade rather than one
## snap. Was `PlayerInputController.CORE_HOP_SLIDE_DELAY` before the walk moved
## into the applier; slightly under SkillNode's slide duration.
const CORE_HOP_SLIDE_DELAY := 0.18


## The FIRST hop only — see [method CommandApplier._drain]'s note. Later hops
## become legal (or not) as their predecessors land, so vetting the whole path
## here would refuse walks that are perfectly legal.
func _validate(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var hops := ctx.resolve_nodes((command as MoveCoreCommand).path_ids)
	return not hops.is_empty() and ctx.allocation_system.can_move_core(actor, hops[0])


## Walk the hops in order, stopping on the first failure — identical to the
## per-hop loop `PlayerInputController._commit_core_move` ran before #510, beat
## and all. "One command" is about the wire, not about atomicity: a partial
## core walk is already a legal observable state (#458 decision 4).
func _apply(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var hops := ctx.resolve_nodes((command as MoveCoreCommand).path_ids)
	if hops.is_empty():
		return false
	for i in hops.size():
		if not ctx.allocation_system.move_core(actor, hops[i]):
			return false
		if i < hops.size() - 1:
			await ctx.tree.create_timer(CORE_HOP_SLIDE_DELAY).timeout
	return true
