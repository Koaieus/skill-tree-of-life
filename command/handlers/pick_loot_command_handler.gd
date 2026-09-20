class_name PickLootCommandHandler
extends CommandHandler

## A remote picker's answer to a parked [LootPickRequest] (#522). Mutates
## nothing itself — it releases a request that a [LootRoundCommand] is parked
## on, and THAT command is the mutation, already mid-apply on the queue.
##
## [b]So it deliberately does not go through the queue[/b]
## ([method bypasses_queue]). Routing it there is not a delay, it is a
## deadlock: [method CommandApplier.submit] appends and returns while
## `is_applying` is true, and the drain cannot reach the appended command
## because the drain is parked on the very await only that command can
## release. The applier's class note already names the shape ("park on a
## signal that cannot fire until the drain it is blocking completes — a hang");
## an answer to an in-flight command is the one case that walks straight into
## it.
##
## It emits neither `command_applied` nor `command_confirmed`, which is also
## correct: an intent travelling UP must not be echoed back down by
## [CommandLink], and the grant it unblocks crosses as the round's own record.
## It never opens the awaiting-confirmation gate on any peer either
## ([method CommandApplier._submit_upward]) — a window nothing would close.
##
## An id that names nothing is a normal outcome — a stale or duplicate pick —
## not an error.


func bypasses_queue() -> bool:
	return true


func validate(_command: Command, ctx: CommandContext) -> bool:
	return ctx.loot_pick_registry != null


func apply(command: Command, ctx: CommandContext) -> bool:
	if ctx.loot_pick_registry == null:
		return false
	var pick := command as PickLootCommand
	return ctx.loot_pick_registry.resolve_pick(pick.request_id, pick.chosen_index)
