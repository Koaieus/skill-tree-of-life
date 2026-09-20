class_name CommandHandler
extends RefCounted

## One verb's gate and mutation (#999), looked up by [CommandRegistry] from the
## command's `TAG` — [CommandApplier] no longer enumerates types by hand.
## Stateless and shared: one instance per verb, everything per-command arrives
## through the command and the [CommandContext].
##
## [b]Validation is not side-effect-free[/b] by design
## (`docs/domain/multiplayer-sync-model.md`): [LaunchAttackCommandHandler]'s
## gate PRODUCES the record it gates on, so [method validate] runs once, on the
## authority, before the confirm — never as a read-only probe.
##
## The default [method validate] / [method apply] resolve the actor once and
## hand it to [method _validate] / [method _apply]; a verb whose actor may
## legitimately be dead ([LootRoundCommandHandler]) overrides the public pair
## instead. The warn/quiet split is deliberate: [method validate] reports an
## unresolvable id, [method apply] runs only after that same id resolved and
## returns quietly rather than warning twice.


## Does this verb skip the applier's serial queue? Only [PickLootCommand] does —
## it answers a request the queue is PARKED on, so queueing it is a deadlock.
func bypasses_queue() -> bool:
	return false


func validate(command: Command, ctx: CommandContext) -> bool:
	var actor := ctx.resolve_actor(command.entity_id)
	if actor == null:
		push_warning("CommandApplier: no entity for id %d (%s)" \
				% [command.entity_id, command.type_tag()])
		return false
	return _validate(command, actor, ctx)


func apply(command: Command, ctx: CommandContext) -> bool:
	var actor := ctx.resolve_actor(command.entity_id)
	if actor == null:
		return false
	@warning_ignore("redundant_await")
	return await _apply(command, actor, ctx)


func _validate(command: Command, _actor: Entity, _ctx: CommandContext) -> bool:
	push_warning("CommandApplier: no validator for command tag '%s'" % command.type_tag())
	return false


func _apply(command: Command, _actor: Entity, _ctx: CommandContext) -> bool:
	push_warning("CommandApplier: no handler for command tag '%s'" % command.type_tag())
	return false
