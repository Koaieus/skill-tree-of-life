extends GutTest

## [CommandApplier] as a queue (#510): submission order, gate isolation,
## re-entrancy, and surviving an async command.
##
## The re-entrancy tests submit from a `command_applied` HANDLER, not from an
## invented entry point — that is the shape the codebase actually re-enters on
## (`ui/gauges/capacity_blips.gd`'s pip-click note, and PIC's own deallocate ->
## cascade-offer fallback), and it only proves anything because
## `command_applied` fires INSIDE the applier's guard.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _applier: CommandApplier
var _player: Entity
var _nodes: Dictionary


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = {}
	for id in ["A", "B", "C", "D"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		_graph.add_skill_node(sn)
		_nodes[id] = sn
	_graph.add_edge(_n("A"), _n("B"))
	_graph.add_edge(_n("B"), _n("C"))
	_graph.add_edge(_n("C"), _n("D"))

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	_alloc.turn_manager = _tm
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container, NOT the Graph itself: entity_id is minted on entry to
	# that container (#509), and a command naming an unminted id resolves to
	# nothing.
	_graph.entities_container.add_child(_player)

	await get_tree().process_frame

	_player.core_location = _n("A")
	_alloc.force_allocate(_player, _n("A"))
	_tm.start_turn(_player)
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.deallocation_points.restore_to_full()
	_player.stat_board.movement_points.restore_to_full()

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.turn_manager = _tm
	add_child_autofree(_applier)


func _n(id: String) -> SkillNode:
	return _nodes[id]


func _allocate(id: String) -> AllocateCommand:
	return AllocateCommand.new(_player.entity_id, _n(id).stable_id)


# ── Ordering ────────────────────────────────────────────────────────────────

func test_the_queue_drains_in_submission_order() -> void:
	var applied: Array[StringName] = []
	_applier.command_applied.connect(func(cmd, _ok): applied.append(cmd.type_tag()))
	_applier.submit(_allocate("B"))
	_applier.submit(DeallocateCommand.new(_player.entity_id, _n("B").stable_id))
	_applier.submit(_allocate("B"))
	assert_eq(applied, [&"allocate", &"deallocate", &"allocate"] as Array[StringName])
	assert_eq(_n("B").owned_by, _player, "and the net effect is the last command's")


func test_a_command_that_fails_its_gate_does_not_stall_the_queue() -> void:
	var outcomes: Array[bool] = []
	_applier.command_applied.connect(func(_cmd, ok): outcomes.append(ok))
	# D is three hops out — not adjacent to the player's territory, so allocate
	# refuses it. B behind it must still land.
	_applier.submit(_allocate("D"))
	_applier.submit(_allocate("B"))
	assert_eq(outcomes, [false, true] as Array[bool], "the refusal is an outcome, not a stall")
	assert_eq(_n("D").owned_by, null)
	assert_eq(_n("B").owned_by, _player)


func test_an_unresolvable_entity_id_fails_without_stalling() -> void:
	var outcomes: Array[bool] = []
	_applier.command_applied.connect(func(_cmd, ok): outcomes.append(ok))
	_applier.submit(AllocateCommand.new(9999, _n("B").stable_id))
	_applier.submit(_allocate("B"))
	assert_eq(outcomes, [false, true] as Array[bool])


# ── Re-entrancy ─────────────────────────────────────────────────────────────

func test_a_command_submitted_from_a_handler_is_queued_not_reentrant() -> void:
	var order: Array[String] = []
	# An Array as the latch, not a bool: GDScript lambdas copy captured locals
	# per invocation, so `reentered = true` inside one would not be visible to
	# the next — and this handler resubmitting forever is an infinite queue.
	var reentered: Array[bool] = [false]
	_applier.command_applied.connect(func(cmd, _ok):
		order.append("applied:" + str(cmd.type_tag()))
		if not reentered[0]:
			reentered[0] = true
			order.append("submit-from-handler")
			_applier.submit(_allocate("C")))
	_applier.submit(_allocate("B"))
	assert_eq(order, [
		"applied:allocate",
		"submit-from-handler",
		"applied:allocate",
	] as Array[String], "the nested command applied AFTER the outer one reported, never inside it")
	assert_eq(_n("C").owned_by, _player, "and it really did apply")


func test_the_guard_is_still_held_while_a_handler_runs() -> void:
	var seen: Array[int] = [-1, -1]  # [applying?, pending count] — see the latch note above
	_applier.command_applied.connect(func(_cmd, _ok):
		if seen[0] != -1:
			return
		seen[0] = 1 if _applier.is_applying else 0
		_applier.submit(_allocate("C"))
		seen[1] = _applier.pending_count())
	_applier.submit(_allocate("B"))
	assert_eq(seen[0], 1,
			"command_applied fires inside the guard — that is what makes the queue real")
	assert_eq(seen[1], 1, "the handler's submission went to the queue, not down the stack")
	assert_false(_applier.is_applying, "and the guard is released once the queue is empty")


func test_applying_changed_brackets_the_whole_drain() -> void:
	var transitions: Array[bool] = []
	_applier.applying_changed.connect(func(applying): transitions.append(applying))
	_applier.command_applied.connect(func(_cmd, _ok):
		if _applier.pending_count() == 0 and _n("C").owned_by == null:
			_applier.submit(_allocate("C")))
	_applier.submit(_allocate("B"))
	assert_eq(transitions, [true, false] as Array[bool],
			"one bracket for the whole drain, not one per command")


func test_applying_changed_false_arrives_after_the_flag_cleared() -> void:
	# Mirrors battle_system.gd:282-289's deliberate ordering: the listener reads
	# the flag the instant the signal fires, so it must already be false.
	var flag_seen: Array[bool] = [true]
	_applier.applying_changed.connect(func(applying):
		if not applying:
			flag_seen[0] = _applier.is_applying)
	_applier.submit(_allocate("B"))
	assert_false(flag_seen[0])


# ── Submitted, awaiting confirmation (#541) ─────────────────────────────────

func test_the_pending_phase_opens_before_anything_is_applying() -> void:
	# `submit` refreshes ahead of the `is_applying` bail on purpose: the command
	# is submitted and the world has not moved, which is the whole phase.
	var applying_at_open: Array[bool] = []
	_applier.awaiting_confirmation_changed.connect(func(awaiting: bool):
		if awaiting:
			applying_at_open.append(_applier.is_applying))
	_applier.submit(_allocate("B"))
	assert_eq(applying_at_open, [false] as Array[bool],
			"the pending phase is the one BEFORE the mutation, not a slice of it")


func test_confirming_is_what_closes_the_pending_phase() -> void:
	var awaiting_at_confirm: Array[bool] = [true]
	_applier.command_confirmed.connect(func(_cmd):
		awaiting_at_confirm[0] = _applier.is_awaiting_confirmation)
	_applier.submit(_allocate("B"))
	assert_false(awaiting_at_confirm[0],
			"the flag already accounts for the decision when the announcement fires")
	assert_false(_applier.is_awaiting_confirmation, "and it stays closed once the queue drains")


func test_awaiting_confirmation_changed_false_arrives_after_the_flag_cleared() -> void:
	# The release hazard #541 names, same shape as the applying_changed one
	# above: PIC reads the flag the instant this fires, and a stale "still
	# pending" would leave AttackModeBar disabled forever.
	var flag_seen: Array[bool] = [true]
	_applier.awaiting_confirmation_changed.connect(func(awaiting: bool):
		if not awaiting:
			flag_seen[0] = _applier.is_awaiting_confirmation)
	_applier.submit(_allocate("B"))
	assert_false(flag_seen[0])


func test_a_refused_command_releases_the_pending_phase() -> void:
	# D is three hops out, so _validate refuses it and it never confirms —
	# nothing else would close the window.
	_applier.submit(_allocate("D"))
	assert_false(_applier.is_awaiting_confirmation)


func test_each_command_gets_its_own_pending_phase() -> void:
	# Not one bracket for the whole drain — that is `applying_changed`'s job. A
	# command submitted from a handler opens a fresh window on the line before
	# the outgoing one would have closed one, which is why the flag is derived.
	var transitions: Array[bool] = []
	_applier.awaiting_confirmation_changed.connect(func(awaiting): transitions.append(awaiting))
	_applier.command_applied.connect(func(_cmd, _ok):
		if _applier.pending_count() == 0 and _n("C").owned_by == null:
			_applier.submit(_allocate("C")))
	_applier.submit(_allocate("B"))
	assert_eq(transitions, [true, false, true, false] as Array[bool],
			"one window per command, the handler's submission included")
	assert_false(_applier.is_awaiting_confirmation)


# ── Async commands ──────────────────────────────────────────────────────────

func test_a_multi_hop_move_core_holds_the_queue_until_the_walk_settles() -> void:
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var order: Array[String] = []
	_applier.command_applied.connect(func(cmd, _ok): order.append(str(cmd.type_tag())))

	var hops: Array[int] = [_n("B").stable_id, _n("C").stable_id]
	_applier.submit(MoveCoreCommand.new(_player.entity_id, hops))
	# The walk parks on its inter-hop beat, so it is still in flight here.
	assert_true(_applier.is_applying, "the guard survives the await, it does not end at hop 1")
	assert_eq(order.size(), 0, "and nothing has reported yet")
	_applier.submit(_allocate("D"))
	assert_eq(_applier.pending_count(), 1, "the second command waits behind the walk")

	await wait_seconds(CommandApplier.CORE_HOP_SLIDE_DELAY * 3.0)
	assert_eq(order, ["move_core", "allocate"] as Array[String],
			"the second command applied only after the walk fully settled")
	assert_eq(_player.core_location, _n("C"), "and the core walked both hops")
	assert_false(_applier.is_applying)


func test_a_move_core_stops_at_the_first_illegal_hop() -> void:
	_alloc.force_allocate(_player, _n("B"))
	# C is owned (hop 2 is legal), D is not — hop 3 must refuse and stop there.
	_alloc.force_allocate(_player, _n("C"))
	var hops: Array[int] = [_n("B").stable_id, _n("C").stable_id, _n("D").stable_id]
	var outcome := [true]
	_applier.command_applied.connect(func(_cmd, ok): outcome[0] = ok)
	_applier.submit(MoveCoreCommand.new(_player.entity_id, hops))
	await wait_seconds(CommandApplier.CORE_HOP_SLIDE_DELAY * 4.0)
	assert_eq(_player.core_location, _n("C"), "the core sits where hop two left it")
	assert_false(outcome[0], "and the command reports the partial walk as a failure")


# ── end_turn ────────────────────────────────────────────────────────────────

func test_end_turn_hands_the_turn_over_and_the_queue_drains() -> void:
	var other: Entity = autofree(Entity.new())
	other.display_name = "Other"
	other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(other)
	await get_tree().process_frame

	_applier.submit(EndTurnCommand.new(_player.entity_id))
	assert_ne(_tm.current_entity, _player, "the turn moved on")
	assert_false(_applier.is_applying)
	assert_eq(_applier.pending_count(), 0)


func test_end_turn_releases_the_guard_without_waiting_on_the_next_turn() -> void:
	# `end_turn()` synchronously ticks initiative, and the entity it hands to
	# may take an ASYNC turn (an AI one) that the applier has no handle on —
	# so the guard is released at end_turn's return, not at that turn's end.
	# Deliberate for child B: routing the AI is #512's job, and there is
	# nothing here to await. Pinned so the next change to this is a decision.
	_applier.submit(EndTurnCommand.new(_player.entity_id))
	assert_false(_applier.is_applying,
			"the guard is already down on the line after submit — nothing was awaited")


# ── mass_allocate recomputes its own budget ─────────────────────────────────

func test_mass_allocate_recomputes_affordable_count_from_the_live_board() -> void:
	var sp: PoolStat = _player.stat_board.skill_points
	sp.deplete(float(sp.available() - 2))  # exactly two hops' worth on the live board
	var path_ids: Array[int] = [
		_n("A").stable_id, _n("B").stable_id, _n("C").stable_id, _n("D").stable_id,
	]
	_applier.submit(MassAllocateCommand.new(_player.entity_id, path_ids))
	assert_eq(_n("B").owned_by, _player)
	assert_eq(_n("C").owned_by, _player)
	assert_eq(_n("D").owned_by, null, "the third hop was never affordable")


# ── command_confirmed: the mirror seam ──────────────────────────────────────

func test_a_synchronous_verb_confirms_immediately_before_it_reports() -> void:
	# The seam costs an ordinary verb nothing: with no tail to wait out, the
	# settle point IS the end of application, so the two fire back to back.
	var order: Array[String] = []
	_applier.command_confirmed.connect(func(cmd): order.append("confirmed:" + str(cmd.type_tag())))
	_applier.command_applied.connect(func(cmd, _ok): order.append("applied:" + str(cmd.type_tag())))
	_applier.submit(_allocate("B"))
	assert_eq(order, ["confirmed:allocate", "applied:allocate"] as Array[String],
			"confirmed always precedes applied, for the same command")


func test_a_refused_command_never_confirms() -> void:
	# What CommandLink used to enforce with `if not success`. A refusal changed
	# nothing, so there is nothing for a peer to mirror — and now that the
	# broadcast rides confirmation, this IS that guarantee.
	var confirmed: Array[String] = []
	_applier.command_confirmed.connect(func(cmd): confirmed.append(str(cmd.type_tag())))
	_applier.submit(_allocate("D"))  # three hops out — refused, see above
	assert_eq(confirmed, [] as Array[String])
	_applier.submit(_allocate("B"))
	assert_eq(confirmed, ["allocate"] as Array[String], "…and a legal one still confirms")


func test_confirm_is_idempotent_so_one_command_crosses_the_wire_once() -> void:
	# Idempotence is what lets `_drain`'s flip point be the ONLY announcement:
	# anything that confirms a second time — a `command_applied` handler, a verb
	# reaching for `confirm` directly — is a no-op rather than a peer applying
	# the command twice. It used to guard a real caller (the attack confirmed
	# mid-apply until #545); it now guards the possibility, and the de-dup is
	# asserted from the far end of the same window, which is the widest it has
	# to hold.
	var confirmed: Array[Command] = []
	_applier.command_confirmed.connect(func(cmd): confirmed.append(cmd))
	var command := _allocate("B")
	_applier.command_applied.connect(func(cmd, _ok): _applier.confirm(cmd))
	_applier.submit(command)
	assert_eq(confirmed.size(), 1, "exactly one confirmation for one command")
	assert_eq(confirmed[0], command)
