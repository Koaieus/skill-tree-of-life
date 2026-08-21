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

## True from the first [method submit] that starts a drain until the queue is
## empty — spanning every await inside every command, not just the mutation.
var is_applying: bool = false

var _queue: Array[Command] = []


## Claim the [BattleSystem] as ours to call back into. Set from here rather
## than by a second NodePath export on [BattleSystem] so the applier it
## submits to and the applier that applies for it are the same object by
## construction — two exports could name two.
func _ready() -> void:
	if battle_system != null:
		battle_system.command_applier = self


## Enqueue [param command]. Drains immediately when idle; when a drain is
## already running this returns at once and the in-flight drain picks the
## command up. Never blocks the caller — even the synchronous verbs finish
## inside this call only because they happen to have nothing to await.
func submit(command: Command) -> void:
	if command == null:
		return
	_queue.append(command)
	if is_applying:
		return
	_drain()


## How many commands are waiting behind the one being applied. Tests read this;
## nothing in production should need it.
func pending_count() -> int:
	return _queue.size()


func _drain() -> void:
	is_applying = true
	applying_changed.emit(true)
	while not _queue.is_empty():
		var command: Command = _queue.pop_front()
		@warning_ignore("redundant_await")
		var success: bool = await _apply(command)
		# Inside the guard, deliberately — see the class note.
		command_applied.emit(command, success)
	is_applying = false
	applying_changed.emit(false)


## Resolve the ids and run the verb. Returns the gated system's verdict.
## Nothing here re-validates: the gated entry points ([method
## AllocationSystem.allocate] and friends) are the authority offline today and
## stay the authority here.
func _apply(command: Command) -> bool:
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
	if command is PickLootCommand:
		# Not routed yet: nothing raises a PickLootCommand, and correlating
		# `request_id` back to its live LootPickRequest needs a registry that
		# #510 deliberately does not build (the loot files are outside its
		# "Files touched"). The type exists from #509; wiring it is a
		# follow-up.
		push_warning("CommandApplier: pick_loot is not routed through the applier yet")
		return false
	push_warning("CommandApplier: no handler for command tag '%s'" % command.type_tag())
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
