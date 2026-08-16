extends GutTest

## PlayerInputController routing for the mass-action confirm flow: a distant
## click arms MassActionArmedMode instead of silently no-oping; a would-island
## deallocate offers the cascade instead of a flat reject; confirm/cancel
## drive AllocationSystem and clear the pending state. Complements
## test/unit/systems/test_mass_action.gd (AllocationSystem primitives) and
## test_manage_verbs.gd (the rest of the click-routing surface).
##
## Uses `graph.add_skill_node`/`add_edge` (not raw container add_child) so
## `graph.navigator` — the global mirror `allocation_path` requires — is
## actually populated (`.claude/rules/graph.md`), unlike test_manage_verbs.gd
## which only exercises adjacent-node routing and never needed it.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity
var _nodes: Dictionary
var _pending_events: Array


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

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_player)

	await get_tree().process_frame

	_player.core_location = _n("A")
	_alloc.force_allocate(_player, _n("A"))

	_tm.start_turn(_player)
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.deallocation_points.restore_to_full()

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.player = _player
	add_child_autofree(_ctl)

	_pending_events = []
	_ctl.mass_action_pending_changed.connect(func(r): _pending_events.append(r))


func _n(id: String) -> SkillNode:
	return _nodes[id]


# ── Allocate: distant click ──────────────────────────────────────────────

func test_distant_click_arms_mass_action_instead_of_no_op() -> void:
	_ctl._on_skill_node_left_clicked(_n("C"))  # 2 hops from A, 5 SP available
	assert_not_null(_ctl.pending_mass_action(), "distant click arms a pending request")
	var request := _ctl.pending_mass_action()
	assert_eq(request.verb, MassActionRequest.Verb.ALLOCATE)
	assert_eq(request.nodes, [_n("A"), _n("B"), _n("C")])
	assert_eq(request.affordable_count, 2, "both hops affordable with 5 SP")


func test_second_click_while_pending_is_a_no_op() -> void:
	_ctl._on_skill_node_left_clicked(_n("C"))
	var first_request := _ctl.pending_mass_action()
	_ctl._on_skill_node_left_clicked(_n("D"))
	assert_eq(_ctl.pending_mass_action(), first_request, "board is frozen while a confirm is pending")


func test_cancel_clears_pending_state() -> void:
	_ctl._on_skill_node_left_clicked(_n("C"))
	assert_not_null(_ctl.pending_mass_action())
	_ctl.cancel_mass_action()
	assert_null(_ctl.pending_mass_action())
	assert_eq(_n("B").owned_by, null, "cancel never allocates anything")


func test_mass_action_armed_mode_pops_via_cancel() -> void:
	var mode := MassActionArmedMode.new(_ctl)
	assert_false(mode.is_armed())
	_ctl._on_skill_node_left_clicked(_n("C"))
	assert_true(mode.is_armed())
	assert_true(mode.pop())
	assert_null(_ctl.pending_mass_action(), "pop cancels the pending request")
	assert_false(mode.is_armed())


func test_confirm_executes_the_affordable_prefix() -> void:
	_ctl._on_skill_node_left_clicked(_n("C"))
	_ctl.confirm_mass_action()
	assert_eq(_n("B").owned_by, _player)
	assert_eq(_n("C").owned_by, _player)
	assert_null(_ctl.pending_mass_action(), "confirm clears the pending state")


# ── Deallocate: would-island click ───────────────────────────────────────

func test_would_island_deallocate_opens_cascade_instead_of_flat_reject() -> void:
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var denials: Array = []
	var handler := func(node, reason): denials.append([node, reason])
	Events.node_action_denied.connect(handler)
	_ctl._resolve_deallocate(_n("B"))  # B is a cut vertex — removing it strands C
	Events.node_action_denied.disconnect(handler)
	assert_not_null(_ctl.pending_mass_action(), "cascade panel opens instead of a plain denial")
	assert_eq(_ctl.pending_mass_action().verb, MassActionRequest.Verb.DEALLOCATE)
	assert_true(_n("B") in _ctl.pending_mass_action().nodes)
	assert_true(_n("C") in _ctl.pending_mass_action().nodes)
	assert_eq(denials.size(), 0, "no flat denial fired — the cascade panel took the click instead")


func test_would_island_deallocate_opens_even_when_dp_is_short() -> void:
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var dp: SurplusPoolStat = _player.stat_board.deallocation_points
	dp.deplete(dp.available())
	dp.set_surplus(1)  # cascade needs 2 DP, player has 1
	_ctl._resolve_deallocate(_n("B"))
	assert_not_null(_ctl.pending_mass_action(), "panel opens regardless of DP sufficiency")
	assert_false(_alloc.can_deallocate_set(_ctl.pending_mass_action().nodes, _player),
			"but the batch itself is correctly unaffordable — panel's Confirm should disable")
