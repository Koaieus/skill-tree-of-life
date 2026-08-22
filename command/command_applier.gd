@tool
class_name CommandApplier
extends Node

## The one place a [Command] becomes a world mutation (#510,
## `docs/domain/multiplayer-sync-model.md`). Every peer — host included — runs
## its confirmed commands through exactly one of these, in submission order.
##
## [b]One serial queue.[/b] [method submit] enqueues and, if nothing is being
## applied, drains. If a drain is already in flight it just enqueues and
## returns: a command raised from inside another command's application is
## QUEUED, never applied re-entrantly. That is not a hardening pass bolted on
## later — the codebase already re-enters on the temp-upgrade path
## (`ui/gauges/capacity_blips.gd`'s `pip_clicked -> ... -> _rebuild()` note),
## so the guard ships on day one.
##
## [b]The queue is ASYNC.[/b] Two verbs are not synchronous:
## [MoveCoreCommand] waits a beat between hops so the slides read as a cascade,
## and [EndTurnCommand] runs [method TurnManager.end_turn], which ticks
## initiative and can start an AI turn. A command may therefore take seconds,
## and [member is_applying] must survive the whole await. This copies the shape
## [member BattleSystem.is_launching] already proved works; it deliberately
## does not reuse that flag, which keeps answering the narrower question "is an
## attack in flight" (owner's clarification on #510).
##
## [b]Signal order is load-bearing.[/b] [signal command_applied] fires INSIDE
## the guard, so a fallback handler that submits (the deallocate -> cascade
## offer does exactly this) is queued rather than re-entering.
## [signal applying_changed] fires after the flag clears — the same ordering
## `battle_system.gd:282-289` documents for `is_launching`, and for the same
## reason: the listener reads the flag the instant the signal arrives.
##
## The flip side of that ordering: a [signal command_applied] handler that
## submits UNCONDITIONALLY never lets the drain end. The queue is FIFO and
## terminates exactly when handlers stop feeding it — there is no re-entrancy
## depth to run out of, so a runaway handler is an infinite loop, not a stack
## overflow. Every fallback here latches (PIC's cascade offer fires only on a
## failed deallocate, and the request it opens waits on the player).

## One command finished applying. [param success] is the gated system's own
## verdict — a command that fails its gate is a normal outcome, not an error,
## and never stalls the ones behind it. Emitted while [member is_applying] is
## still true, on purpose (see above).
signal command_applied(command: Command, success: bool)

## One command's WIRE PAYLOAD is final and its world mutation is done — mirror
## it now. Fires at most once per command, always before that command's
## [signal command_applied], and only for a command that succeeded.
##
## [b]Why this is not just [signal command_applied].[/b] Application spans more
## than mutation. [method BattleSystem._commit] deliberately keeps awaiting
## after the world has settled — it holds `is_launching` until the animation
## tail finishes, so a player cannot arm and fire again mid-swing. Mirroring off
## `command_applied` therefore made a peer wait out the HOST's animation before
## it could start its own (#511 shipped that way), which reads as lag
## proportional to spell length. Nothing about the payload changes in that
## window: [AttackRecord] is stamped the instant the mutation ends.
##
## A verb that has such a tail calls [method confirm] at its settle point; every
## other verb needs nothing, because [method _drain] confirms on its behalf.
## Ordering across commands is unchanged either way — the queue is serial, so a
## mid-apply confirm still lands between its neighbours' confirms.
signal command_confirmed(command: Command)

## [member is_applying] transitioned. Consumers gate input off this
## ([method PlayerInputController.can_player_act]); it is not an outcome
## signal.
signal applying_changed(applying: bool)

## Beat between hops of a [MoveCoreCommand], so a multi-hop walk reads as a
## cascade rather than one snap. Was `PlayerInputController.CORE_HOP_SLIDE_DELAY`
## before the walk moved in here; slightly under SkillNode's slide duration.
const CORE_HOP_SLIDE_DELAY := 0.18

@export var graph: Graph
@export var allocation_system: AllocationSystem
@export var battle_system: BattleSystem
@export var turn_manager: TurnManager

## The outstanding-loot-pick book, for [PickLootCommand] (#522).
@export var loot_pick_registry: LootPickRegistry

## Is this peer the one that DECIDES, or the one that is told? True offline,
## true on the host, false only while [member CommandLink.mode] is `MIRROR` —
## that setter is the single writer, so nothing has to be kept in sync by hand
## and no scene grows a second role flag.
##
## Almost nothing reads this: a command's application is deliberately the same
## code on every peer, and [LaunchAttackCommand] carries which half of the work
## is already done in its own payload rather than asking about a role. The
## exception is a mutation a peer STARTS on its own, from a local reaction
## rather than from a received command — [SkillDustAddon]'s claim flow opens on
## `owner_changed`, which fires on every peer that applies the allocation. That
## one needs gating; see its `_on_carrier_owner_changed`.
var is_authority: bool = true

## True from the first [method submit] that starts a drain until the queue is
## empty — spanning every await inside every command, not just the mutation.
var is_applying: bool = false

var _queue: Array[Command] = []

## The command [method confirm] has already announced, so [method _drain] does
## not announce it twice. A single slot, not a set: the queue is serial and
## non-re-entrant, so only one command is ever mid-apply.
var _confirmed: Command = null


## Claim the [BattleSystem] as ours to call back into. Set from here rather
## than by a second NodePath export on [BattleSystem] so the applier it
## submits to and the applier that applies for it are the same object by
## construction — two exports could name two.
## `@tool` so a sandbox panel can drive the real queue in-editor (the melee tab
## does). Nothing auto-drives: a drain only ever starts from [method submit].
func _ready() -> void:
	if battle_system != null:
		battle_system.command_applier = self


## Enqueue [param command]. Drains immediately when idle; when a drain is
## already running this returns at once and the in-flight drain picks the
## command up. Never blocks the caller — even the synchronous verbs finish
## inside this call only because they happen to have nothing to await.
##
## [PickLootCommand] is the one exception and takes [method _answer_loot_pick]
## instead — see there for why the queue is exactly the wrong place for it.
func submit(command: Command) -> void:
	if command == null:
		return
	if command is PickLootCommand:
		_answer_loot_pick(command as PickLootCommand)
		return
	_queue.append(command)
	if is_applying:
		return
	_drain()


## How many commands are waiting behind the one being applied. Tests read this;
## nothing in production should need it.
func pending_count() -> int:
	return _queue.size()


## "This command's world mutation is done and its payload is final" — called by
## a verb that keeps awaiting afterwards, to release the mirror early. Only ever
## call it once the verb knows it SUCCEEDED; a refused command changed nothing
## and must not cross the wire. Idempotent, and safe to call from a verb that is
## running without an applier only because the caller null-checks first.
func confirm(command: Command) -> void:
	if command == null or _confirmed == command:
		return
	_confirmed = command
	command_confirmed.emit(command)


func _drain() -> void:
	is_applying = true
	applying_changed.emit(true)
	while not _queue.is_empty():
		var command: Command = _queue.pop_front()
		@warning_ignore("redundant_await")
		var success: bool = await _apply(command)
		# For everything without an animation tail this IS the settle point, so
		# the two signals fire back to back and the seam costs nothing. A verb
		# that already confirmed mid-apply makes this a no-op.
		if success:
			confirm(command)
		# Inside the guard, deliberately — see the class note.
		command_applied.emit(command, success)
		# Cleared only once this command is fully reported, so the de-dup covers
		# a `command_applied` handler that confirms too. Nothing is leaked by
		# holding it one line longer: the next iteration overwrites it.
		_confirmed = null
	is_applying = false
	applying_changed.emit(false)


## Resolve the ids and run the verb. Returns the gated system's verdict.
## Nothing here re-validates: the gated entry points ([method
## AllocationSystem.allocate] and friends) are the authority offline today and
## stay the authority here.
func _apply(command: Command) -> bool:
	# Ahead of the actor lookup, deliberately: a relic's TERMINAL round runs
	# after its collector may already be dead and freed, and it is the record
	# that frees the relic on every peer. Resolving an actor first would drop it.
	if command is LootRoundCommand:
		@warning_ignore("redundant_await")
		return await _apply_loot_round(command as LootRoundCommand)
	var actor := graph.get_by_entity_id(command.entity_id) if graph != null else null
	if actor == null:
		push_warning("CommandApplier: no entity for id %d (%s)" \
				% [command.entity_id, command.type_tag()])
		return false
	if command is NodeCommand:
		return _apply_node_command(command as NodeCommand, actor)
	if command is MoveCoreCommand:
		return await _apply_move_core(command as MoveCoreCommand, actor)
	if command is MassAllocateCommand:
		return _apply_mass_allocate(command as MassAllocateCommand, actor)
	if command is DeallocateSetCommand:
		var nodes := _resolve_nodes((command as DeallocateSetCommand).node_ids)
		return allocation_system.deallocate_set(nodes, actor)
	if command is LaunchAttackCommand:
		if battle_system == null:
			return false
		@warning_ignore("redundant_await")
		return await battle_system.apply_launch_command(command as LaunchAttackCommand)
	if command is EndTurnCommand:
		if turn_manager == null:
			return false
		turn_manager.end_turn()
		return true
	push_warning("CommandApplier: no handler for command tag '%s'" % command.type_tag())
	return false


## A remote picker's answer to a parked [LootPickRequest] (#522). Mutates
## nothing itself — it releases a request that a [LootRoundCommand] is parked
## on, and THAT command is the mutation, already mid-apply on the queue.
##
## [b]So it deliberately does not go through the queue.[/b] Routing it there is
## not a delay, it is a deadlock: [method submit] appends and returns while
## [member is_applying] is true, and the drain cannot reach the appended
## command because the drain is parked on the very await only that command can
## release. This file's class note already names the shape ("park on a signal
## that cannot fire until the drain it is blocking completes — a hang"); an
## answer to an in-flight command is the one case that walks straight into it.
##
## It emits neither [signal command_applied] nor [signal command_confirmed],
## which is also correct: an intent travelling UP must not be echoed back down
## by [CommandLink], and the grant it unblocks crosses as the round's own
## record.
##
## An id that names nothing is a normal outcome — a stale or duplicate pick —
## not an error.
func _answer_loot_pick(command: PickLootCommand) -> bool:
	if loot_pick_registry == null:
		return false
	return loot_pick_registry.resolve_pick(command.request_id, command.chosen_index)


## One round of a relic's claim flow (#522). The addon does the work — this
## only resolves the carrier and hands over. INITIATE awaits the whole round,
## the player's pick included, which is deliberate: [member is_applying] stays
## true for the duration, so the existing
## [method PlayerInputController.can_player_act] gate is what enforces the
## owner's "no ending the turn while picking" rule, and the End Turn button
## greys out through `player_can_act_changed` rather than silently no-opping.
func _apply_loot_round(command: LootRoundCommand) -> bool:
	var carrier := _resolve_node(command.carrier_id)
	if carrier == null:
		push_warning("CommandApplier: no relic node for stable_id %d (loot_round)"
				% command.carrier_id)
		return false
	# Resolved here rather than read off `carrier.owned_by` in the addon: the
	# command names its collector by `entity_id` precisely so both peers grant
	# to the same entity. May legitimately be null on a terminal round, whose
	# whole job is to free the relic after its collector is gone.
	var collector := graph.get_by_entity_id(command.entity_id) if graph != null else null
	for addon in carrier.get_addons():
		if addon is SkillDustAddon:
			@warning_ignore("redundant_await")
			return await (addon as SkillDustAddon).run_round(command, collector)
	push_warning("CommandApplier: node %d carries no SkillDustAddon (loot_round)"
			% command.carrier_id)
	return false


func _apply_node_command(command: NodeCommand, actor: Entity) -> bool:
	var node := _resolve_node(command.node_id)
	if node == null:
		push_warning("CommandApplier: no node for stable_id %d (%s)" \
				% [command.node_id, command.type_tag()])
		return false
	if command is AllocateCommand:
		return allocation_system.allocate(node, actor)
	if command is DeallocateCommand:
		return allocation_system.deallocate(node, actor)
	if command is StakeCommand:
		return allocation_system.stake(node, actor)
	if command is ExtractCommand:
		return allocation_system.extract(node, actor)
	if command is ToggleTempUpgradeCommand:
		if battle_system == null:
			return false
		var upgrade := MeleeAttackPlan.upgrade_by_id(
				(command as ToggleTempUpgradeCommand).upgrade_id)
		return battle_system.toggle_temp_upgrade_on(node, upgrade)
	push_warning("CommandApplier: no handler for node command '%s'" % command.type_tag())
	return false


## Walk the hops in order, stopping on the first failure — identical to the
## per-hop loop `PlayerInputController._commit_core_move` ran before #510, beat
## and all. "One command" is about the wire, not about atomicity: a partial
## core walk is already a legal observable state (#458 decision 4).
func _apply_move_core(command: MoveCoreCommand, actor: Entity) -> bool:
	var hops := _resolve_nodes(command.path_ids)
	if hops.is_empty():
		return false
	for i in hops.size():
		if not allocation_system.move_core(actor, hops[i]):
			return false
		if i < hops.size() - 1:
			await get_tree().create_timer(CORE_HOP_SLIDE_DELAY).timeout
	return true


## [member MassAllocateCommand.path_ids] carries the path ONLY — how much of it
## the actor can pay for is recomputed here, never taken from the sender, so a
## stale peer cannot dictate how much the authority spends (#458 decision).
func _apply_mass_allocate(command: MassAllocateCommand, actor: Entity) -> bool:
	var path := _resolve_nodes(command.path_ids)
	var affordable := allocation_system.affordable_allocation_count(actor, path)
	if affordable < 1:
		return false
	return allocation_system.mass_allocate(actor, path, affordable) > 0


func _resolve_node(id: int) -> SkillNode:
	return graph.get_by_stable_id(id) if graph != null else null


## Ids -> live nodes, dropping any that no longer resolve. A dropped node is a
## node that left the graph between submission and application; the gated verb
## behind this is what decides whether the remainder is still legal.
func _resolve_nodes(ids: Array[int]) -> Array[SkillNode]:
	var nodes: Array[SkillNode] = []
	for id in ids:
		var node := _resolve_node(id)
		if node != null:
			nodes.append(node)
	return nodes
