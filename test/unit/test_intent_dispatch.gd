extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Intent-by-channel dispatch (issue #60). With turn phases gone,
## PlayerInputController disambiguates player intent by INPUT CHANNEL, each
## gated only by "is it your turn?" + its own budget:
##   - bare left-click on an unowned adjacent node  → allocate
##   - hover a node + press `D`                      → deallocate
##   - left-click your own core                      → enter core-move targeting
##
## In-memory graph: a 3-node line A–B–C. Player owns A (its core); B and C are
## adjacent frontier. No navigator is wired, so islanding checks are skipped
## (AllocationSystem documents that path) — these tests isolate the routing.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _applier: CommandApplier
var _player: Entity
var _other: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])  # A–B
	_add_edge(_nodes[1], _nodes[2])  # B–C

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	# A second entity so we can hand the turn away from the player (otherwise
	# the lone player immediately retakes its own turn after end_turn).
	_other = autofree(Entity.new())
	_other.display_name = "Other"
	_other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_other)

	await get_tree().process_frame

	# Player owns A as its core. B, C are unowned frontier.
	_nodes[0].owned_by = _player
	_player.core_location = _nodes[0]

	_tm.start_turn(_player)

	# Deterministic budgets (independent of whether turn-start upkeep ran).
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.deallocation_points.restore_to_full()
	_player.stat_board.movement_points.restore_to_full()
	# AP=0 so the battle channel bails before touching the (unset) BattleSystem.
	var ap: PoolStat = _player.stat_board.action_points
	ap.deplete(int(ap.current))

	# #510: the controller asks for mutations as Commands now, so a fixture
	# that clicks needs the applier that turns them back into system calls.
	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.turn_manager = _tm
	_ctl.command_applier = _applier
	_ctl.player = _player
	add_child_autofree(_ctl)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _press_d() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_D
	ev.pressed = true
	_ctl._unhandled_input(ev)


func _press_right_click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	_ctl._unhandled_input(ev)


# ── Allocate channel: bare left-click on an unowned adjacent node ───────────

func test_left_click_unowned_adjacent_allocates() -> void:
	assert_eq(_nodes[1].owned_by, null, "precondition: B starts unowned")
	_nodes[1].left_clicked.emit(_nodes[1])
	assert_eq(_nodes[1].owned_by, _player, "bare left-click on adjacent unowned node allocates it")


func test_left_click_non_adjacent_does_not_allocate() -> void:
	# C is not adjacent to any owned node (only B is). allocate() rejects it.
	_nodes[2].left_clicked.emit(_nodes[2])
	assert_eq(_nodes[2].owned_by, null, "non-adjacent node is not allocated by a click")


func test_left_click_owned_node_with_stake_headroom_refills() -> void:
	# B staked to cap 2 but still filled 1 — a bare click must refill it
	# (#337's refill is otherwise unreachable: the manage-verb dispatcher has
	# no ALLOCATE case, and this was the only other click channel that
	# touches allocate()).
	_nodes[1].owned_by = _player
	_nodes[1].stake_level = 2
	_nodes[1].allocation_level = 1
	_nodes[1].left_clicked.emit(_nodes[1])
	assert_eq(_nodes[1].allocation_level, 2, "bare left-click refills a staked, owned node")


func test_left_click_owned_full_node_does_not_refill() -> void:
	# B owned and already at cap — nothing to refill, click is a no-op.
	_nodes[1].owned_by = _player
	_nodes[1].stake_level = 1
	_nodes[1].allocation_level = 1
	_nodes[1].left_clicked.emit(_nodes[1])
	assert_eq(_nodes[1].allocation_level, 1, "a full node is not over-filled by a click")


func test_left_click_not_players_turn_does_nothing() -> void:
	# Hand the turn to the other entity so the player is no longer current.
	_other.stat_board.initiative.restore_to_full()  # readies _other (joins ready group)
	_tm.end_turn()
	assert_eq(_tm.current_entity, _other, "precondition: other entity holds the turn")
	_nodes[1].left_clicked.emit(_nodes[1])
	assert_eq(_nodes[1].owned_by, null, "clicks do nothing when it isn't the player's turn")


# ── Deallocate channel: hover + `D` ────────────────────────────────────────

func test_d_on_hovered_owned_node_deallocates() -> void:
	_nodes[1].owned_by = _player  # B already allocated
	Events.skill_node_hovered.emit(_nodes[1])
	_press_d()
	assert_eq(_nodes[1].owned_by, null, "pressing D while hovering an owned node deallocates it")


func test_d_with_nothing_hovered_is_noop() -> void:
	_nodes[1].owned_by = _player
	Events.skill_node_unhovered.emit()  # nothing hovered
	_press_d()
	assert_eq(_nodes[1].owned_by, _player, "D with no hovered node deallocates nothing")


func test_d_on_hovered_core_does_not_deallocate() -> void:
	# The core is owned but is_core() — deallocate() rejects it.
	Events.skill_node_hovered.emit(_nodes[0])
	_press_d()
	assert_eq(_nodes[0].owned_by, _player, "the core node cannot be deallocated via D")


# ── Move-core channel: left-click own core enters targeting ────────────────

func test_left_click_own_core_enters_targeting() -> void:
	var sources: Array = []
	_ctl.core_move_targeting_changed.connect(func(s: SkillNode) -> void: sources.append(s))
	_nodes[0].left_clicked.emit(_nodes[0])
	assert_eq(sources.size(), 1, "clicking own core fires core_move_targeting_changed once")
	assert_eq(sources[0], _nodes[0], "targeting source is the core node")


# ── #404: right-click / D-key / Esc interplay with an armed core-move ──────

func test_right_click_cancels_core_move_targeting() -> void:
	_nodes[0].left_clicked.emit(_nodes[0])  # arm core-move on own core
	assert_not_null(_ctl.move_targeting_source(), "precondition: core-move armed")
	_press_right_click()  # right-click — pops regardless of which/whether a node is hovered
	assert_null(_ctl.move_targeting_source(),
			"right-click pops core-move regardless of which node it landed on")


func test_esc_cancels_core_move_targeting() -> void:
	_nodes[0].left_clicked.emit(_nodes[0])  # arm core-move
	assert_not_null(_ctl.move_targeting_source(), "precondition: core-move armed")
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	_ctl._unhandled_key_input(esc)
	assert_null(_ctl.move_targeting_source(), "Esc pops the armed core-move")


func test_d_gated_while_core_move_targeting_active() -> void:
	_nodes[1].owned_by = _player  # B already allocated, otherwise deallocatable
	_nodes[0].left_clicked.emit(_nodes[0])  # arm core-move on own core
	assert_not_null(_ctl.move_targeting_source(), "precondition: core-move armed")
	Events.skill_node_hovered.emit(_nodes[1])
	_press_d()
	assert_eq(_nodes[1].owned_by, _player,
			"D is gated off while core-move targeting is armed (#404)")
