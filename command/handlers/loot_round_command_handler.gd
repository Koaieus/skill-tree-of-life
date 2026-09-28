class_name LootRoundCommandHandler
extends CommandHandler

## The loot round controller (#522, #646, #1138): drives a relic's claim and
## replays its rounds. [SkillDustAddon] only describes what it offers and lands
## what it is told; everything that sequences, waits or talks to the pipeline
## is here, in two halves that must stay apart.
##
## [b]Resolve side[/b] — [method open_round] / [method resolve_next], authority
## only, OUTSIDE any command's application: offer, wait for the pick, roll,
## then mint a [LootRoundCommand] with the outcome ALREADY STAMPED and submit
## it through [member CommandContext.command_applier]'s ordinary queue. Kept
## out of [method apply] on purpose: a human pick can take a real round trip,
## and holding [member CommandApplier.is_applying] across it is what #646
## acceptance 3 forbids; and a round resolved inside apply would be resolved on
## EVERY peer, each rolling its own offer.
##
## [b]Replay side[/b] — [method apply], every peer including the authority:
## land the stamped outcome through the addon's grant contract, free the relic
## on the final round, and on the authority fire (never await) the next
## resolve. The grant happens only here, never at resolve time, or the
## authority would grant twice.
##
## With no applier on the context (headless fixture, editor, sandbox relic)
## there is no queue to submit to: the resolve side self-replays through the
## same landing, granting the very instance it drew.
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
	if _dust_on(carrier) != null:
		return true
	push_warning("CommandApplier: node %d carries no SkillDustAddon (loot_round)"
			% round.carrier_id)
	return false


## The replay. [param command]'s collector is resolved by `entity_id` so every
## peer grants to the same entity; legitimately null on a terminal round.
func apply(command: Command, ctx: CommandContext) -> bool:
	var round := command as LootRoundCommand
	var carrier := ctx.resolve_node(round.carrier_id)
	if carrier == null:
		return false
	var dust := _dust_on(carrier)
	if dust == null:
		return false
	_land(dust, round.granted_modifier(), round.granted_spell(), round.is_final(),
			ctx.resolve_actor(round.entity_id), ctx)
	return true


## Open a claim on [param dust] for [param collector] and start resolving.
## The caller owns the host gate: only the authority (or a pipeline-less world)
## may open a claim — a peer's copy of the relic is driven purely by the
## rounds that arrive, or it would roll its own offer in parallel with the
## host's. Opens the applier's outstanding-loot count, which the final round's
## landing closes under the same authority gate.
func open_round(dust: SkillDustAddon, collector: Entity, ctx: CommandContext,
		rounds_count: int = -1) -> void:
	dust.begin_claim(collector, dust.rounds if rounds_count < 0 else rounds_count)
	if ctx.command_applier != null:
		ctx.command_applier.notify_loot_round_opened()
	resolve_next(dust, ctx)  # fired, not awaited


## Resolve whichever round the claim is on next, up to a stamped outcome, then
## settle it. NEVER grants. A stat round with one survivor auto-grants without a
## picker; an empty phase falls through to the next one.
func resolve_next(dust: SkillDustAddon, ctx: CommandContext) -> void:
	if dust.phase == SkillDustAddon.Phase.STAT:
		var offer: Array[StatModifier] = []
		offer.assign(dust.offers_for(SkillDustAddon.Phase.STAT))
		if not offer.is_empty():
			var chosen: StatModifier = offer[0]
			if offer.size() > 1:
				var request := LootPickRequest.new(dust.claim_collector, offer, Callable())
				Events.loot_pick_requested.emit(request)
				var picked: Array = await _await_pick(request, offer, dust.claim_collector,
						ctx.loot_pick_registry)
				chosen = picked[0] if not picked.is_empty() else null
			if not dust.has_live_claimant():
				chosen = null
			dust.consume_stat_round(chosen)
			_settle(dust, ctx, chosen, null, false)
			return
		dust.end_stat_phase()
	if dust.phase == SkillDustAddon.Phase.SPELL:
		var spells: Array[SpellDef] = []
		spells.assign(dust.offers_for(SkillDustAddon.Phase.SPELL))
		dust.phase = SkillDustAddon.Phase.TERMINAL
		if not spells.is_empty():
			var request := SpellLootRequest.new(dust.claim_collector, spells, Callable())
			Events.spell_loot_requested.emit(request)
			var picked: Array = await _await_pick(request, spells, dust.claim_collector,
					ctx.loot_pick_registry)
			var spell: SpellDef = picked[0] if not picked.is_empty() else null
			if not dust.has_live_claimant():
				spell = null
			_settle(dust, ctx, null, spell, false)
			return
	_settle(dust, ctx, null, null, true)


## A decided outcome becomes a [LootRoundCommand] here and nowhere else — the
## constructor takes the outcome, so none exists before this point. Submitted
## through the applier's ordinary queue, never applied directly. Without an
## applier, self-replay the exact objects picked (a runtime-minted
## [StatModifier] has no wire identity; only the wire branch narrows a spell to
## its id).
func _settle(dust: SkillDustAddon, ctx: CommandContext, granted: StatModifier,
		spell: SpellDef, finished: bool) -> void:
	var applier := ctx.command_applier
	if applier == null:
		_land(dust, granted, spell, finished, dust.claim_collector, ctx)
		return
	var collector_id := dust.claim_collector.entity_id \
			if is_instance_valid(dust.claim_collector) else 0
	var carrier_id := 0
	if applier.graph != null:
		carrier_id = applier.graph.get_stable_id(dust.carrier)
	var spell_id := spell.id if spell != null else &""
	applier.submit(LootRoundCommand.new(collector_id, carrier_id, granted, spell_id, finished))


## Grant, free on [param finished], and — only on the authority, only once the
## grant has landed — fire the next resolve. Fired, never awaited: awaiting it
## from [method apply] would hold the queue for the rest of the claim again.
## The next round's `would_cycle` filter sees this grant because it has landed.
##
## A peer's pool is never trimmed (only the resolve side does that), so its
## tooltip lists an already-granted candidate for the seconds the claim takes;
## cosmetic, and the pool is freed at `finished`.
func _land(dust: SkillDustAddon, granted: StatModifier, spell: SpellDef, finished: bool,
		collector: Entity, ctx: CommandContext) -> void:
	if collector == null and dust.carrier != null:
		collector = dust.carrier.owned_by
	if is_instance_valid(collector) and not collector.is_dead:
		if granted != null:
			dust.grant_mod(collector, granted)
		if spell != null:
			dust.grant_spell(collector, spell)
	var applier := ctx.command_applier
	if finished:
		# Symmetric with the one open in [method open_round], which only the
		# authority reaches — a mirror never opened, so it must not close, or
		# the counter underflows.
		if applier != null and applier.is_authority:
			applier.notify_loot_round_closed()
		dust.finish()
		return
	if applier == null or applier.is_authority:
		resolve_next(dust, ctx)  # fired, not awaited


## Park on the pick, whoever is making it. THE HANDSHAKE (see [LootPickRequest]):
## a HUD that presents the choice claims it SYNCHRONOUSLY inside the emit, so
## `claim` already says who is picking.
##
##   * `LOCAL` — a picker on this machine is up; await its confirm.
##   * `REMOTE` — a human on another peer owes the answer; park it in the
##     registry (which fires the [LootPickOffer], addressed to that peer) so
##     the returning [PickLootCommand] can land. Live in real play: the roster
##     and peer id are wired at [method GameRoot.apply_roster].
##   * `UNCLAIMED` — NPC / headless / no HUD: a random 1 of the offer. A
##     HOST-ONLY roll, exempt from seeding (`.claude/rules/multiplayer-sync.md`):
##     the peer receives the result, it does not reproduce it.
##
## [b]Owner call 2026-08-27: a collector that dies while this await is parked
## forfeits the round[/b] rather than leaving it stuck — reachable because the
## pick runs outside the queue (#646), so anything else may act meanwhile.
func _await_pick(request: Variant, offer: Array, collector: Entity,
		registry: LootPickRegistry) -> Array:
	if request.claim == LootPickRequest.Claim.UNCLAIMED \
			and registry != null and registry.is_remote_collector(collector):
		request.claim = LootPickRequest.Claim.REMOTE
		registry.park(request)
	if request.claim == LootPickRequest.Claim.UNCLAIMED:
		var pool := offer.duplicate()
		pool.shuffle()
		return [pool[0]]
	if request.is_resolved():
		return []
	var forfeit_on_death := Callable()
	if is_instance_valid(collector):
		forfeit_on_death = func() -> void:
			if not request.is_resolved():
				request.resolve(_forfeit_like(request))
		collector.died.connect(forfeit_on_death, CONNECT_ONE_SHOT)
	@warning_ignore("redundant_await")
	var chosen: Array = await request.settled
	if forfeit_on_death.is_valid() and is_instance_valid(collector) \
			and collector.died.is_connected(forfeit_on_death):
		collector.died.disconnect(forfeit_on_death)
	return chosen


## The correctly-typed empty array for whichever request kind [param request] is.
func _forfeit_like(request: Variant) -> Array:
	if request is SpellLootRequest:
		return [] as Array[SpellDef]
	return [] as Array[StatModifier]


func _dust_on(carrier: SkillNode) -> SkillDustAddon:
	for addon in carrier.get_addons():
		if addon is SkillDustAddon:
			return addon as SkillDustAddon
	return null
