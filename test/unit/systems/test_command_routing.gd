extends GutTest

## #510 — [PlayerInputController]'s terminal calls go out as [Command]s through
## [CommandApplier], and the outcomes come back as signals. Covers the reroute
## itself (one command per multi-hop core move, denial feedback that used to be
## an inline `if` branch), the widened `can_player_act()` gate, and the
## temp-upgrade path that moved to [BattleSystem].
##
## The queue's own behaviour (ordering, re-entrancy, async commands) is
## `test/unit/command/test_command_applier.gd`; this file is about the wiring
## either side of it.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _applier: CommandApplier
var _ctl: PlayerInputController
var _player: Entity
var _nodes: Dictionary
var _denials: Array


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

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	add_child_autofree(_alloc)

	_battle = autofree(BattleSystem.new())
	add_child(_battle)

	_tm = autofree(TurnManager.new())
	add_child(_tm)
	_alloc.turn_manager = _tm
	_battle.turn_manager = _tm
	_battle.allocation_system = _alloc
	_battle.graph = _graph

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	await get_tree().process_frame

	_player.core_location = _n("A")
	_alloc.force_allocate(_player, _n("A"))
	_tm.start_turn(_player)
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.deallocation_points.restore_to_full()
	_player.stat_board.action_points.restore_to_full()
	_player.stat_board.movement_points.restore_to_full()

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.battle_system = _battle
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.command_applier = _applier
	_ctl.player = _player
	add_child_autofree(_ctl)

	_denials = []
	Events.node_action_denied.connect(_on_denied)


func after_each() -> void:
	if Events.node_action_denied.is_connected(_on_denied):
		Events.node_action_denied.disconnect(_on_denied)


func _on_denied(node: SkillNode, reason: String) -> void:
	_denials.append([node, reason])


func _n(id: String) -> SkillNode:
	return _nodes[id]


func _tags() -> Array[StringName]:
	var seen: Array[StringName] = []
	_applier.command_applied.connect(func(cmd, _ok): seen.append(cmd.type_tag()))
	return seen


# ── The reroute itself ──────────────────────────────────────────────────────

func test_a_bare_click_allocates_through_a_command() -> void:
	var seen := _tags()
	_ctl._on_skill_node_left_clicked(_n("B"))
	assert_eq(seen, [&"allocate"] as Array[StringName])
	assert_eq(_n("B").owned_by, _player, "and it really landed")


func test_no_mutation_path_on_the_controller_returns_a_bool() -> void:
	# The acceptance grep, as a test: the verbs are submitters now, and the
	# outcome is a signal. A `bool` here would mean a caller could still branch
	# on success inline, which is exactly what could not survive a wire.
	for verb in ["_resolve_deallocate", "_resolve_stake", "_resolve_extract",
			"_commit_core_move", "confirm_mass_action"]:
		var sig: Dictionary = {}
		for m in _ctl.get_method_list():
			if m.name == verb:
				sig = m
		assert_false(sig.is_empty(), "%s still exists" % verb)
		assert_eq(sig.return.type, TYPE_NIL, "%s must not return a value" % verb)


func test_apply_armed_temp_upgrade_to_is_gone_from_the_controller() -> void:
	assert_false(_ctl.has_method("apply_armed_temp_upgrade_to"),
			"it moved to BattleSystem.toggle_temp_upgrade_on (#510)")
	assert_true(_ctl.has_method("request_temp_upgrade_at"),
			"what stays behind is the arm + the routing answer")
	assert_true(_battle.has_method("toggle_temp_upgrade_on"))


# ── Multi-hop core move: ONE command ────────────────────────────────────────

func test_a_multi_hop_core_move_issues_exactly_one_command() -> void:
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var seen := _tags()
	_ctl._commit_core_move(_n("C"))
	assert_eq(_applier.pending_count(), 0,
			"nothing queued behind it — the walk is the single in-flight command")
	await wait_seconds(CommandApplier.CORE_HOP_SLIDE_DELAY * 3.0)
	assert_eq(seen, [&"move_core"] as Array[StringName],
			"two hops, one MoveCoreCommand — never one command per hop")
	assert_eq(_player.core_location, _n("C"))


func test_a_core_move_whose_last_hop_is_illegal_stops_where_it_could() -> void:
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	# Only 2 MP: the walk to C is affordable, a third hop would not be.
	var mp: PoolStat = _player.stat_board.movement_points
	mp.deplete(float(mp.available() - 2))
	_ctl._commit_core_move(_n("C"))
	await wait_seconds(CommandApplier.CORE_HOP_SLIDE_DELAY * 3.0)
	assert_eq(_player.core_location, _n("C"), "identical to the per-hop loop it replaced")


# ── Outcomes that used to be inline `if` branches ───────────────────────────

func test_a_refused_stake_still_shakes_the_node() -> void:
	# D is unowned — can_stake refuses, and the denial now travels back as a
	# command_applied(false) rather than a `bool` return.
	_ctl._resolve_stake(_n("D"))
	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0][0], _n("D"))
	assert_eq(_denials[0][1], "stake_denied_not_owned")


func test_a_refused_extract_still_shakes_the_node() -> void:
	_ctl._resolve_extract(_n("D"))
	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0][1], "extract_denied_not_owned")


func test_a_would_island_deallocate_still_opens_the_cascade_panel() -> void:
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	_ctl._resolve_deallocate(_n("B"))  # B is a cut vertex — removing it strands C
	assert_not_null(_ctl.pending_mass_action(),
			"the fallback branch survived the move into the outcome handler")
	assert_eq(_ctl.pending_mass_action().verb, MassActionRequest.Verb.DEALLOCATE)
	assert_eq(_denials.size(), 0, "and no flat denial fired instead")


func test_the_cascade_offer_is_queued_not_applied_reentrantly() -> void:
	# The failing deallocate's handler opens a mass action, whose confirm
	# submits again. That second submission must go through the queue — this is
	# the shape `ui/gauges/capacity_blips.gd` documents as a re-entrancy hazard.
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var applying_when_offered: Array[bool] = [false]
	_ctl.mass_action_pending_changed.connect(func(request):
		if request != null:
			applying_when_offered[0] = _applier.is_applying)
	_ctl._resolve_deallocate(_n("B"))
	assert_true(applying_when_offered[0],
			"the offer was raised INSIDE the guard — anything it submits queues")
	_ctl.confirm_mass_action()
	assert_eq(_n("B").owned_by, null)
	assert_eq(_n("C").owned_by, null, "the whole cascade went")


# ── Temp upgrades: the path capacity_blips flagged as re-entrant ────────────

## Arms a melee plan with A (pivot) - B - C as blade members and a clamp armed
## on the controller, which is the state a tray pip click acts in.
func _arm_melee_with_clamp() -> void:
	_player.stat_board.blade_size.base_value = 3.0
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	_battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _battle.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_n("A"))
	plan._on_node_left_clicked(_n("B"))
	plan._on_node_left_clicked(_n("C"))
	_ctl.arm_temp_upgrade(MeleeAttackPlan.upgrade_by_id(&"clamp"))


func test_an_armed_temp_upgrade_lands_through_the_applier() -> void:
	_arm_melee_with_clamp()
	var seen := _tags()
	assert_true(_ctl.request_temp_upgrade_at(_n("C")), "the click is consumed")
	assert_eq(seen, [&"toggle_temp_upgrade"] as Array[StringName])
	assert_false(_n("C").get_addons().is_empty(), "and the addon is really mounted")


func test_a_toggle_raised_from_a_plan_state_listener_is_queued() -> void:
	# `attack_plan_state_changed` is what drives MeleeBody._refresh ->
	# CapacityBlips._rebuild, whose comment documents the synchronous
	# re-entrancy hazard on `pip_clicked -> apply_armed_temp_upgrade_to ->
	# _rebuild()`. That listener now fires while the applier holds its guard,
	# so a re-entrant toggle is structurally impossible rather than merely
	# survivable.
	_arm_melee_with_clamp()
	var applying_when_notified: Array[bool] = [false]
	var reentrant_consumed: Array[bool] = [true]
	var fired: Array[bool] = [false]
	_battle.attack_plan_state_changed.connect(func():
		if fired[0]:
			return
		fired[0] = true
		applying_when_notified[0] = _applier.is_applying
		reentrant_consumed[0] = _ctl.request_temp_upgrade_at(_n("B")))
	_ctl.request_temp_upgrade_at(_n("C"))
	assert_true(applying_when_notified[0],
			"the rebuild-triggering signal fires inside the applier's guard")
	assert_false(reentrant_consumed[0],
			"and can_player_act() — now reading is_applying — refuses the click outright")
	assert_true(_n("B").get_addons().is_empty(), "so no second toggle snuck in mid-apply")
	assert_false(_n("C").get_addons().is_empty(), "while the one the player asked for landed")


func test_a_raw_submit_from_that_same_listener_queues_rather_than_reenters() -> void:
	# The gate above is the first line of defence; the queue is the structural
	# one. Bypass the gate (a peer's confirmed command arrives this way, with no
	# can_player_act() in the path) and the applier still refuses to re-enter.
	_arm_melee_with_clamp()
	var pending_inside: Array[int] = [-1]
	var fired: Array[bool] = [false]
	_battle.attack_plan_state_changed.connect(func():
		if fired[0]:
			return
		fired[0] = true
		_applier.submit(ToggleTempUpgradeCommand.new(
				_player.entity_id, _graph.get_stable_id(_n("B")), &"clamp"))
		pending_inside[0] = _applier.pending_count())
	_ctl.request_temp_upgrade_at(_n("C"))
	assert_eq(pending_inside[0], 1, "queued, not applied down the stack")
	# Whether the queued toggle then LANDS is the plan's own budget call (the
	# shared blade_size may well be spent by the first one) — the point here is
	# that it was applied in its turn and the queue drained, not re-entrantly.
	assert_eq(_applier.pending_count(), 0)
	assert_false(_applier.is_applying)


# ── The widened act gate ────────────────────────────────────────────────────

func test_can_player_act_is_false_while_a_non_attack_command_applies() -> void:
	var seen: Array[bool] = [true, false]  # [during, after]
	_applier.command_applied.connect(func(_cmd, _ok):
		seen[0] = _ctl.can_player_act())
	_ctl._on_skill_node_left_clicked(_n("B"))
	seen[1] = _ctl.can_player_act()
	assert_false(seen[0], "an allocation is landing — this is not a moment to click")
	assert_true(seen[1], "and the gate reopens once the queue drains")


func test_the_gate_signal_fires_on_both_edges_of_a_drain() -> void:
	var gate: Array[bool] = []
	_ctl.player_can_act_changed.connect(func(can_act): gate.append(can_act))
	_ctl._on_skill_node_left_clicked(_n("B"))
	assert_true(gate.has(false) and gate.has(true),
			"UI hears the gate close and reopen; %s" % str(gate))
	assert_eq(gate.back(), true, "and settles open")


func test_is_launching_still_gates_independently() -> void:
	# Nested guards, not merged (owner's clarification on #510): is_launching
	# keeps answering "an attack is in flight" on its own.
	_battle.is_launching = true
	assert_false(_ctl.can_player_act())
	_battle.is_launching = false
	assert_true(_ctl.can_player_act())
	assert_false(_applier.is_applying, "and it never touched the applier's flag")
