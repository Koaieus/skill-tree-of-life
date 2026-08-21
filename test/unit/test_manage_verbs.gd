extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Manage-tab verb dispatch (#338): Stake/Extract/Deallocate arm via
## PlayerInputController.arm_manage_verb, then resolve on the next legal node
## click through the #404 shared dispatcher. Complements test_intent_dispatch.gd
## (bare-click allocate / D-hover-deallocate / core-move), which this doesn't
## re-cover.
##
## In-memory graph: a 4-node line A–B–C–D. Player owns A (core) and B (1 hop,
## stakeable/extractable target) via AllocationSystem.force_allocate — unlike
## test_intent_dispatch's direct `owned_by` writes, this also mirrors into
## EntityNavigator, which _core_within_one_hop needs. C is owned but 2 hops
## from the core (not-adjacent denial target). D stays unowned (not-owned
## denial target).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _applier: CommandApplier
var _hl: HighlightController
var _player: Entity
var _nodes: Array[SkillNode]
## [[node, reason], ...] logged by _on_denied. Events is a global autoload, so
## the handler is connected/disconnected per-test rather than left dangling —
## GUT doesn't reset autoloads between tests (.claude/rules/testing.md).
var _denials: Array


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])  # A–B
	_add_edge(_nodes[1], _nodes[2])  # B–C
	_add_edge(_nodes[2], _nodes[3])  # C–D

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_battle = autofree(BattleSystem.new())
	add_child(_battle)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	await get_tree().process_frame

	_player.core_location = _nodes[0]
	_alloc.force_allocate(_player, _nodes[0])  # core, mirrors into navigator
	_alloc.force_allocate(_player, _nodes[1])  # 1 hop — legal stake/extract target
	_alloc.force_allocate(_player, _nodes[2])  # 2 hops — owned but not adjacent

	_tm.start_turn(_player)

	# Generous budgets — tests isolate routing/gating, not resource math.
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.deallocation_points.restore_to_full()
	_player.stat_board.action_points.restore_to_full()

	# #510: the controller asks for mutations as Commands now, so a fixture
	# that clicks needs the applier that turns them back into system calls.
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

	_hl = autofree(HighlightController.new())
	_hl.allocation_system = _alloc
	_hl.graph = _graph
	_hl.player = _player
	_hl.input_ctl = _ctl
	_hl.turn_manager = _tm
	# _ready's signal wiring never runs (HighlightController isn't added to the
	# tree here) — tests call _hl._resolve() directly, same pattern as
	# test_highlight_controller.gd.


func after_each() -> void:
	if Events.node_action_denied.is_connected(_on_denied):
		Events.node_action_denied.disconnect(_on_denied)


func _on_denied(node: SkillNode, reason: String) -> void:
	_denials.append([node, reason])


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


# ── Stake ────────────────────────────────────────────────────────────────

func test_arming_stake_then_clicking_legal_node_stakes() -> void:
	assert_eq(_nodes[1].stake_level, 1, "precondition: B starts at stake_level 1")
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	var sp_before: int = _player.stat_board.skill_points.available()
	var ap_before: int = _player.stat_board.action_points.available()
	_nodes[1].left_clicked.emit(_nodes[1])
	assert_eq(_nodes[1].stake_level, 2, "arm Stake + click legal node raises stake_level")
	assert_eq(_player.stat_board.skill_points.available(), sp_before - 1, "stake spends 1 SP into staked")
	assert_eq(_player.stat_board.action_points.available(), ap_before - 1, "stake spends 1 AP")


func test_stake_click_on_illegal_node_denies_and_spends_nothing() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	var sp_before: int = _player.stat_board.skill_points.available()
	var ap_before: int = _player.stat_board.action_points.available()
	_nodes[2].left_clicked.emit(_nodes[2])  # owned but 2 hops from core
	assert_eq(_nodes[2].stake_level, 1, "illegal stake click does not raise stake_level")
	assert_eq(_player.stat_board.skill_points.available(), sp_before, "no SP spent on denial")
	assert_eq(_player.stat_board.action_points.available(), ap_before, "no AP spent on denial")
	assert_eq(_denials.size(), 1, "denial fires exactly once")
	assert_eq(_denials[0][0], _nodes[2], "denial targets the clicked node")
	assert_eq(_denials[0][1], "stake_denied_not_adjacent", "denial reason names the >1-hop gate")


func test_stake_click_on_unowned_node_denies_not_owned() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	_nodes[3].left_clicked.emit(_nodes[3])  # unowned
	var reasons: Array = _denials.map(func(d: Array) -> String: return d[1])
	assert_eq(reasons, ["stake_denied_not_owned"], "unowned node denies with not_owned reason")


func test_stake_stays_armed_after_a_denial() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	_nodes[3].left_clicked.emit(_nodes[3])  # illegal — denied
	assert_eq(_ctl.manage_arm(), PlayerInputController.ManageVerb.STAKE,
			"a denied click doesn't disarm Stake — right-click/Esc cancels explicitly")


# ── Extract ──────────────────────────────────────────────────────────────

func test_arming_extract_then_clicking_staked_node_extracts() -> void:
	_alloc.stake(_nodes[1], _player)  # bring B to stake_level 2 so it's extractable
	assert_eq(_nodes[1].stake_level, 2, "precondition: B staked to level 2")
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.EXTRACT)
	var dp_before: int = _player.stat_board.deallocation_points.available()
	_nodes[1].left_clicked.emit(_nodes[1])
	assert_eq(_nodes[1].stake_level, 1, "arm Extract + click legal node drops stake_level")
	assert_eq(_player.stat_board.deallocation_points.available(), dp_before - 1, "extract spends 1 DP")


func test_extract_click_on_floor_node_denies_at_floor() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.EXTRACT)
	_nodes[1].left_clicked.emit(_nodes[1])  # stake_level 1 — nothing to extract
	var reasons: Array = _denials.map(func(d: Array) -> String: return d[1])
	assert_eq(reasons, ["extract_denied_at_floor"], "a 1/1 node denies extract at the floor, not a deallocate")


# ── Deallocate (armed click, distinct from D-hover) ─────────────────────

func test_arming_deallocate_then_clicking_owned_node_deallocates() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.DEALLOCATE)
	_nodes[2].left_clicked.emit(_nodes[2])  # owned, non-core, non-islanding
	assert_null(_nodes[2].owned_by, "arm Deallocate + click legal node deallocates it")


func test_armed_deallocate_click_on_core_denies() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.DEALLOCATE)
	_nodes[0].left_clicked.emit(_nodes[0])  # core — can_deallocate rejects
	assert_eq(_nodes[0].owned_by, _player, "the core cannot be deallocated via the armed click either")
	var reasons: Array = _denials.map(func(d: Array) -> String: return d[1])
	assert_eq(reasons, ["deallocate_denied"], "armed click on an illegal node fires denial (unlike unarmed D-hover)")


func test_d_hover_deallocate_still_works_unarmed() -> void:
	Events.skill_node_hovered.emit(_nodes[2])
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_D
	ev.pressed = true
	_ctl._unhandled_input(ev)
	assert_null(_nodes[2].owned_by, "D-hover-deallocate is unchanged by the #338 refactor")


# ── Right-click cancels an armed Manage verb ────────────────────────────

func test_right_click_cancels_armed_manage_verb() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	assert_eq(_ctl.manage_arm(), PlayerInputController.ManageVerb.STAKE, "precondition: Stake armed")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	_ctl._unhandled_input(ev)
	assert_eq(_ctl.manage_arm(), PlayerInputController.ManageVerb.NONE,
			"right-click pops an armed Manage verb instead of falling through to pin-toggle")


# ── Allocate's arm is cosmetic — it must not swallow other channels ────────

func test_right_click_still_pins_while_allocate_armed() -> void:
	# Allocate's arm is view-affordance only (cursor + card highlight) — it
	# must not join the pop stack, or the first right-click after clicking
	# the Allocate card would silently disarm instead of pinning.
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.ALLOCATE)
	Events.skill_node_hovered.emit(_nodes[2])
	var pinned: Array = []
	_ctl.node_pinned.connect(func(n: SkillNode) -> void: pinned.append(n))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	_ctl._unhandled_input(ev)
	assert_eq(pinned, [_nodes[2]], "right-click still pins the hovered node while Allocate is armed")


func test_d_hover_deallocate_still_works_while_allocate_armed() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.ALLOCATE)
	Events.skill_node_hovered.emit(_nodes[2])
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_D
	ev.pressed = true
	_ctl._unhandled_input(ev)
	assert_null(_nodes[2].owned_by, "D-hover-deallocate isn't gated off by a merely-cosmetic Allocate arm")


# ── Highlight reachability tinting (HighlightController → ManagerHighlightProvider) ──

func test_stake_armed_tints_legal_target_in_range_and_leaves_non_adjacent_none() -> void:
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	_hl._resolve()
	assert_eq(_hl.provider.get_node_role(_nodes[1]), HighlightProvider.HighlightRole.IN_RANGE,
			"Stake-armed: the 1-hop legal target is tinted IN_RANGE")
	assert_eq(_hl.provider.get_node_role(_nodes[2]), HighlightProvider.HighlightRole.NONE,
			"Stake-armed: the 2-hop node (not adjacent) gets no tint")


func test_extract_armed_tints_only_a_staked_node() -> void:
	_alloc.stake(_nodes[1], _player)  # B now stake_level 2, extractable
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.EXTRACT)
	_hl._resolve()
	assert_eq(_hl.provider.get_node_role(_nodes[1]), HighlightProvider.HighlightRole.IN_RANGE,
			"Extract-armed: a staked 1-hop node is tinted IN_RANGE")
	assert_eq(_hl.provider.get_node_role(_nodes[2]), HighlightProvider.HighlightRole.NONE,
			"Extract-armed: an unstaked node (nothing to extract) gets no tint")


func test_idle_still_tints_allocatable_unowned_nodes() -> void:
	# No verb armed — the pre-#338 default. D (unowned, adjacent to owned C)
	# stays ALLOCATABLE, unchanged by the #338 refactor.
	_hl._resolve()
	assert_eq(_hl.provider.get_node_role(_nodes[3]), HighlightProvider.HighlightRole.ALLOCATABLE,
			"idle Manage mode still tints an allocatable unowned node")
