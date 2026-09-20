class_name LootRoundCommandHandler
extends CommandHandler

## One round of a relic's claim flow (#522). The addon does the work — this only
## resolves the carrier and hands over.
##
## Overrides the public pair rather than the actor hooks, deliberately: a
## relic's TERMINAL round runs after its collector may already be dead and
## freed, and it is the record that frees the relic on every peer. Resolving an
## actor first would drop it.


## A relic round is legal when its carrier still resolves and still carries the
## addon that runs it. A null collector is NOT a failure — a terminal round's
## whole job is to free the relic after its collector is gone.
func validate(command: Command, ctx: CommandContext) -> bool:
	var round := command as LootRoundCommand
	var carrier := ctx.resolve_node(round.carrier_id)
	if carrier == null:
		push_warning("CommandApplier: no relic node for stable_id %d (loot_round)"
				% round.carrier_id)
		return false
	for addon in carrier.get_addons():
		if addon is SkillDustAddon:
			return true
	push_warning("CommandApplier: node %d carries no SkillDustAddon (loot_round)"
			% round.carrier_id)
	return false


## INITIATE awaits the whole round, the player's pick included, which is
## deliberate: [member CommandApplier.is_applying] stays true for the duration,
## so the existing [method PlayerInputController.can_player_act] gate is what
## enforces the owner's "no ending the turn while picking" rule, and the End
## Turn button greys out through `player_can_act_changed` rather than silently
## no-opping.
func apply(command: Command, ctx: CommandContext) -> bool:
	var round := command as LootRoundCommand
	var carrier := ctx.resolve_node(round.carrier_id)
	if carrier == null:
		return false
	# Resolved here rather than read off `carrier.owned_by` in the addon: the
	# command names its collector by `entity_id` precisely so both peers grant
	# to the same entity. May legitimately be null on a terminal round, whose
	# whole job is to free the relic after its collector is gone.
	var collector := ctx.resolve_actor(round.entity_id)
	for addon in carrier.get_addons():
		if addon is SkillDustAddon:
			@warning_ignore("redundant_await")
			return await (addon as SkillDustAddon).run_round(round, collector)
	return false
