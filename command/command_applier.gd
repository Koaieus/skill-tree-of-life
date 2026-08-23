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

## One command's WIRE PAYLOAD is final and it is GOING to be applied — mirror it
## now. Fires at most once per command, always before that command's
## [signal command_applied], and never for a command that failed its gate.
##
## [b]Since #540 this fires BEFORE the mutation, not after it.[/b] That is the
## ordering flip: [method _validate] is the gate, so "validated" already means
## "will apply", and the authority no longer has to finish mutating before it can
## tell anyone. Confirm-after-apply structurally put every peer one full mutation
## window behind the authority — see #534.
##
## [b]Why this is not just [signal command_applied].[/b] Two separate reasons,
## and both still hold:
##   * Application spans more than mutation. [method BattleSystem._commit] keeps
##     awaiting after the world has settled, holding `is_launching` until the
##     animation tail finishes so a player cannot arm and fire again mid-swing.
##     Mirroring off `command_applied` made a peer wait out the HOST's animation
##     before starting its own (#511 shipped that way) — lag proportional to
##     spell length.
##   * `command_applied` fires for a REFUSED command too, with success false. A
##     refusal changed nothing and must never cross the wire.
##
## [b]No verb opts out of this ordering (#545).[/b] [LaunchAttackCommand] was the
## last that did — its [AttackRecord] was computed inside the apply, so
## confirming first would have broadcast an empty record that a peer reads as an
## initiate it cannot run. Moving that compute into
## [method BattleSystem.prepare_launch_command], which [method _validate] calls,
## made its payload final at the same point as everyone else's, and the hook it
## opted out through is gone rather than left standing with no callers.
signal command_confirmed(command: Command)

## [member is_applying] transitioned. Consumers gate input off this
## ([method PlayerInputController.can_player_act]); it is not an outcome
## signal.
signal applying_changed(applying: bool)

## [member is_awaiting_confirmation] transitioned. Same job as
## [signal applying_changed] and the same ordering guarantee — the flag is
## already updated when this arrives — so the two feed one refresh route in
## [PlayerInputController], never two.
signal awaiting_confirmation_changed(awaiting: bool)

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

## [b]Submitted, awaiting confirmation[/b] (#541) — a command has been handed to
## this applier and the authority has not yet decided it is going ahead. The
## world has not moved and the player must not act.
##
## [b]Zero-length locally for every verb (#545).[/b] [method submit] drains
## synchronously down to [method _validate], so on a peer that DECIDES this is
## true for a stack frame. It is not dead code: it is the round trip on a peer
## that is told, which is what #463 opens, and it is the only phase name that
## fits the window — [member BattleSystem.is_launching] means "an attack is in
## flight" and [member is_applying] means "a mutation is under way", and neither
## is true yet.
##
## The attack used to be the exception and the LONG one, spanning its whole
## resolve + mutation loop because it confirmed late. It no longer is: its
## resolve happens inside the validate this flag closes on, so the window is a
## stack frame here too — the same shape, not a special case with a shorter tail.
##
## [b]Nested inside [member is_applying] everywhere but one place.[/b] The gate
## is an OR ([method PlayerInputController.can_player_act]) and on every path but
## that one the OR cannot change the answer. The exception is the first
## [method submit] of a drain: this flips true BEFORE `is_applying` does, which
## is both the honest reading — the command is submitted, nothing is applying
## yet — and the only moment the third gate is the sole reason the player cannot
## act. Do not "simplify" it to a read after the pop.
var is_awaiting_confirmation: bool = false

var _queue: Array[Command] = []

## The command [method _drain] has popped and not finished reporting, or null
## between commands. Exists only so [method _refresh_awaiting] can DERIVE its
## answer rather than have it assigned from five places — a `command_applied`
## handler that submits (the deallocate -> cascade offer does) opens a fresh
## pending window on the line before the outgoing command would have closed one,
## and a derived flag gets that right without an ordering rule to remember.
var _in_flight: Command = null

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
	# Ahead of the `is_applying` bail, deliberately — see
	# [member is_awaiting_confirmation]. On the first submit of a drain this is
	# the transition that fires while nothing is applying yet, and a listener
	# reading the gate in that handler must see it closed.
	_refresh_awaiting()
	if is_applying:
		return
	_drain()


## How many commands are waiting behind the one being applied. Tests read this;
## nothing in production should need it.
func pending_count() -> int:
	return _queue.size()


## "This command's payload is final and it is going to be applied" — announce it
## to the mirror. [method _drain] calls this for every verb at the flip point,
## and since #545 nothing else calls it in production; it stays public and
## idempotent because that is what makes the flip point the ONLY announcement
## even when something announces twice.
##
## Only ever call it once the command is known to be GOING AHEAD — a refused
## command changed nothing and must not cross the wire. Idempotent, and safe to
## call from a verb that is running without an applier only because the caller
## null-checks first.
func confirm(command: Command) -> void:
	if command == null or _confirmed == command:
		return
	_confirmed = command
	# BEFORE the announcement, so a [signal command_confirmed] handler —
	# [CommandLink]'s broadcast is one — reads a flag that already accounts for
	# this decision. Same hazard [signal applying_changed] documents, one signal
	# earlier. (It stays true if something is queued behind: the flag asks
	# "anything undecided", not "is THIS one decided".)
	_refresh_awaiting()
	command_confirmed.emit(command)


## [b]validate -> confirm -> apply[/b] (#540), for every verb without exception
## (#545). The ordering flip: the authority decides a command is legal, announces
## it, and only THEN mutates — so [method _apply] is the shared
## post-confirmation apply every peer runs, authority included, instead of the
## authority's mutation being what a confirm reports after the fact.
##
## [b]The gate moved; it did not multiply.[/b] [method _validate] asks the same
## `can_*` queries the mutating verbs already ask themselves
## ([method AllocationSystem.can_allocate] and friends), so a command that
## validates is a command that will apply. That is what makes confirming first
## safe, and it is why the gate must never be re-derived here — a second copy of
## a rule is the shape `.claude/rules/` forbids.
##
## [b]One verb's validate also PRODUCES.[/b] [LaunchAttackCommand]'s gate is
## "resolve the attack, then check the attacker can afford what came out", and
## the resolution it has to run IS the command's wire payload. So
## [method BattleSystem.prepare_launch_command] resolves (on a shadow — nothing
## real moves) and stamps the record from inside the validate, which is what let
## #545 delete the last confirm-after-apply exception. Do not read `_validate` as
## side-effect-free; read it as "the command is final and legal, or it is
## refused".
##
## The two verbs where validate cannot fully answer for apply are known and
## deliberate: [MoveCoreCommand] can only vet its FIRST hop (a partial core walk
## is a legal observable state, #458 decision 4), and [MassAllocateCommand]
## re-computes its affordable count at apply time on purpose (#458 — a stale
## sender must never dictate how much the authority spends). Both still land
## identically on every peer, because every peer applies the same command
## through this same method.
func _drain() -> void:
	is_applying = true
	applying_changed.emit(true)
	while not _queue.is_empty():
		var command: Command = _queue.pop_front()
		_in_flight = command
		# Stamped BEFORE the gate, for EVERY command on EVERY peer (#540
		# decision 4) — this is the world the command is about to be applied to,
		# and both sides compare pre-state against pre-state. Uniform rather than
		# staged: nothing has to unwind when [LaunchAttackCommand] stops being
		# an exception. See [member Command.pre_fingerprint].
		if graph != null:
			command.pre_fingerprint = WorldFingerprint.compute(graph)
		var success := _validate(command)
		if success:
			# THE FLIP, and since #545 there is no branch around it: every verb
			# reaches here with its whole payload final, the attack included —
			# [method BattleSystem.prepare_launch_command] stamped its record
			# inside the validate above.
			confirm(command)
			@warning_ignore("redundant_await")
			success = await _apply(command)
		# Inside the guard, deliberately — see the class note. Fires for a
		# validate-fail too, with success false: a refused command is a normal
		# outcome and [method PlayerInputController._on_command_applied] is what
		# turns it into player feedback, including the deallocate -> cascade
		# offer. Skipping the emit on a validate-fail would silently delete that.
		command_applied.emit(command, success)
		# Cleared only once this command is fully reported, so the de-dup covers
		# a `command_applied` handler that confirms too. Nothing is leaked by
		# holding it one line longer: the next iteration overwrites it.
		_confirmed = null
		_in_flight = null
		# After BOTH are cleared, or the derivation below would read "in flight,
		# unconfirmed" and re-open a window that just closed. This is where a
		# command REFUSED by [method _validate] releases — it never confirmed, so
		# nothing else would have.
		_refresh_awaiting()
	is_applying = false
	applying_changed.emit(false)


## Recompute [member is_awaiting_confirmation] from what the queue actually
## holds, and announce a transition. Derived rather than assigned: "something is
## submitted and undecided" is exactly `queued, or popped and not yet
## confirmed`, and every call site below is a point where one of those changed.
##
## Flag first, emit second — [method PlayerInputController._emit_gate_changed]
## reads the gate the instant the signal arrives, and a listener that saw a stale
## "still pending" would leave `AttackModeBar` disabled forever (#541; the same
## hazard `battle_system.gd:489-494` documents for `is_launching`).
func _refresh_awaiting() -> void:
	var awaiting := not _queue.is_empty() \
			or (_in_flight != null and _confirmed != _in_flight)
	if awaiting == is_awaiting_confirmation:
		return
	is_awaiting_confirmation = awaiting
	awaiting_confirmation_changed.emit(awaiting)


## Is [param command] legal against the world as it stands right now? The gate,
## and since #540 the ONLY gate that decides whether a command confirms.
##
## For [LaunchAttackCommand] it is also where the payload is produced — see
## [method _drain]'s note, and do not assume every branch here is read-only.
##
## Dispatches exactly as [method _apply] does, and for the same reason — the two
## must never disagree about which verb a command is. What it must not do is
## re-implement any verb's rules: every branch below forwards to the owning
## system's own `can_*` query, which the mutating call then asks again. That
## second ask is not a duplicate check, it is the mutating method keeping its
## own guarantees for its non-command callers.
##
## Diagnostics for an unresolvable id live HERE rather than in [method _apply],
## because a command that fails to resolve now fails before the apply runs —
## leaving the warning downstream would lose it.
func _validate(command: Command) -> bool:
	# Ahead of the actor lookup for the same reason [method _apply] is: a
	# relic's terminal round legitimately has no live collector.
	if command is LootRoundCommand:
		return _validate_loot_round(command as LootRoundCommand)
	var actor := graph.get_by_entity_id(command.entity_id) if graph != null else null
	if actor == null:
		push_warning("CommandApplier: no entity for id %d (%s)" \
				% [command.entity_id, command.type_tag()])
		return false
	if command is NodeCommand:
		return _validate_node_command(command as NodeCommand, actor)
	if command is MoveCoreCommand:
		# The FIRST hop only — see [method _drain]'s note. Later hops become
		# legal (or not) as their predecessors land, so vetting the whole path
		# here would refuse walks that are perfectly legal.
		var hops := _resolve_nodes((command as MoveCoreCommand).path_ids)
		return not hops.is_empty() and allocation_system.can_move_core(actor, hops[0])
	if command is MassAllocateCommand:
		# The same "can it pay for at least one hop" question [method
		# _apply_mass_allocate] asks, through the same one implementation.
		var path := _resolve_nodes((command as MassAllocateCommand).path_ids)
		return allocation_system.affordable_allocation_count(actor, path) >= 1
	if command is DeallocateSetCommand:
		var nodes := _resolve_nodes((command as DeallocateSetCommand).node_ids)
		return allocation_system.can_deallocate_set(nodes, actor)
	if command is LaunchAttackCommand:
		# The one branch that PRODUCES as well as decides — see the method note.
		# The attack's real gate is "resolve, then check affordability", and the
		# resolution it needs is the command's own record; #545 moved both here
		# from the apply so the record is final before the confirm.
		return battle_system != null \
				and battle_system.prepare_launch_command(command as LaunchAttackCommand)
	if command is EndTurnCommand:
		# No gate, deliberately: [method TurnManager.end_turn] has never had one
		# and neither did the direct call it replaced (see
		# [method PlayerInputController.request_end_turn]). Do not invent one.
		return turn_manager != null
	push_warning("CommandApplier: no validator for command tag '%s'" % command.type_tag())
	return false


func _validate_node_command(command: NodeCommand, actor: Entity) -> bool:
	var node := _resolve_node(command.node_id)
	if node == null:
		push_warning("CommandApplier: no node for stable_id %d (%s)" \
				% [command.node_id, command.type_tag()])
		return false
	if command is AllocateCommand:
		return allocation_system.can_allocate(node, actor)
	if command is DeallocateCommand:
		return allocation_system.can_deallocate(node, actor)
	if command is StakeCommand:
		return allocation_system.can_stake(node, actor)
	if command is ExtractCommand:
		return allocation_system.can_extract(node, actor)
	if command is ToggleTempUpgradeCommand:
		if battle_system == null:
			return false
		var upgrade := MeleeAttackPlan.upgrade_by_id(
				(command as ToggleTempUpgradeCommand).upgrade_id)
		# Announces its own refusal, where the reason (slot full vs. budget) is
		# knowable — the applier never emits gameplay denials itself. This is why
		# the gate is a method on [BattleSystem] and not an expression here.
		return battle_system.can_toggle_temp_upgrade_on(node, upgrade)
	push_warning("CommandApplier: no validator for node command '%s'" % command.type_tag())
	return false


## A relic round is legal when its carrier still resolves and still carries the
## addon that runs it. A null collector is NOT a failure — a terminal round's
## whole job is to free the relic after its collector is gone.
func _validate_loot_round(command: LootRoundCommand) -> bool:
	var carrier := _resolve_node(command.carrier_id)
	if carrier == null:
		push_warning("CommandApplier: no relic node for stable_id %d (loot_round)"
				% command.carrier_id)
		return false
	for addon in carrier.get_addons():
		if addon is SkillDustAddon:
			return true
	push_warning("CommandApplier: node %d carries no SkillDustAddon (loot_round)"
			% command.carrier_id)
	return false


## Resolve the ids and run the verb — the shared post-confirmation apply, run by
## every peer including the authority.
##
## Its null-guards below are structural, not gates: [method _validate] has
## already resolved the same ids and reported anything that failed, so these
## return quietly rather than warning twice.
func _apply(command: Command) -> bool:
	# Ahead of the actor lookup, deliberately: a relic's TERMINAL round runs
	# after its collector may already be dead and freed, and it is the record
	# that frees the relic on every peer. Resolving an actor first would drop it.
	if command is LootRoundCommand:
		@warning_ignore("redundant_await")
		return await _apply_loot_round(command as LootRoundCommand)
	var actor := graph.get_by_entity_id(command.entity_id) if graph != null else null
	if actor == null:
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
	return false


func _apply_node_command(command: NodeCommand, actor: Entity) -> bool:
	var node := _resolve_node(command.node_id)
	if node == null:
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
