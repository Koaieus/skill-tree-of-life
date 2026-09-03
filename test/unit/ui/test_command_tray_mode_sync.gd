extends GutTest
## #464: two CommandTray mode buttons could be lit at once / the wrong one lit.
##
## Root cause (confirmed by repro, not just the original diagnosis): a request
## `BattleSystem.request_attack_mode` silently drops — AP=0, or mid-swing,
## since `is_launching` flips true with no signal of its own
## (`player_input_controller.gd:220-226`) — never fires `attack_plan_changed`,
## so `AttackModeBar.set_active_mode` never runs and the native click's own
## visual is left showing a mode that was never actually armed.
##
## Exercises the REAL [Button]/[ButtonGroup] pair, not a mock: assigning
## `button_pressed` (unlike `set_pressed_no_signal`) goes through Godot's own
## exclusivity pass, same as an actual click.

const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _COMMAND_TRAY_SCENE := preload("res://ui/hud/command_tray/command_tray.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity
var _tray: CommandTray
var _bar: AttackModeBar


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	var nodes: Array[SkillNode] = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		_graph.skill_nodes_container.add_child(sn)
		nodes.append(sn)
	_add_edge(nodes[0], nodes[1])
	_add_edge(nodes[1], nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_battle = autofree(BattleSystem.new())
	_battle.graph = _graph
	_battle.turn_manager = _tm
	add_child(_battle)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	await get_tree().process_frame

	_player.core_location = nodes[0]
	_alloc.force_allocate(_player, nodes[0])
	_alloc.force_allocate(_player, nodes[1])

	_tm.start_turn(_player)
	_player.stat_board.action_points.restore_to_full()

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.player = _player
	add_child_autofree(_ctl)

	_tray = _COMMAND_TRAY_SCENE.instantiate()
	add_child_autofree(_tray)
	_tray.bind(_battle, _ctl)
	_tray.set_player(_player)
	_bar = _tray.attack_mode_bar


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _buttons() -> Array[AttackModeButton]:
	var out: Array[AttackModeButton] = []
	for b in _bar.get_children():
		if b is AttackModeButton:
			out.append(b)
	return out


func _pressed_count() -> int:
	var n := 0
	for b in _buttons():
		if b.button_pressed:
			n += 1
	return n


func _by_mode(mode: BattleSystem.AttackMode) -> AttackModeButton:
	for b in _buttons():
		if b.attack_mode == mode:
			return b
	return null


## Real-click stand-in: flips the native `button_pressed` property (enforces
## ButtonGroup exclusivity, unlike `set_pressed_no_signal`) then fires the raw
## `pressed` signal the bar listens to — the same pair a real mouse click
## produces, without needing a SubViewport (`.claude/rules/testing.md`).
func _click(btn: AttackModeButton) -> void:
	btn.button_pressed = true
	btn.pressed.emit()


func _lit_mode() -> BattleSystem.AttackMode:
	for b in _buttons():
		if b.button_pressed:
			return b.attack_mode
	return BattleSystem.AttackMode.NONE


func test_exactly_one_lit_across_a_mix_of_clicks() -> void:
	_click(_by_mode(BattleSystem.AttackMode.MELEE))
	assert_eq(_pressed_count(), 1, "after arming melee")
	assert_eq(_lit_mode(), BattleSystem.AttackMode.MELEE)

	_click(_by_mode(BattleSystem.AttackMode.RANGED))
	assert_eq(_pressed_count(), 1, "after switching to ranged")
	assert_eq(_lit_mode(), BattleSystem.AttackMode.RANGED)

	# Programmatic call (a peer's confirmed state, a hot-seat resync, ...).
	_bar.set_active_mode(BattleSystem.AttackMode.MAGIC)
	assert_eq(_pressed_count(), 1, "after a programmatic set_active_mode")
	assert_eq(_lit_mode(), BattleSystem.AttackMode.MAGIC)


func test_reclick_active_tab_cancels_to_manage_without_double_lighting() -> void:
	_click(_by_mode(BattleSystem.AttackMode.RANGED))
	_click(_by_mode(BattleSystem.AttackMode.RANGED))
	assert_eq(_pressed_count(), 1, "cancel must not leave two lit")
	assert_eq(BattleSystem.AttackMode.NONE, _battle.attack_mode)
	assert_eq(_lit_mode(), BattleSystem.AttackMode.NONE, "Manage reads as mode NONE")


func test_rejected_request_at_zero_ap_leaves_the_bar_on_the_armed_mode() -> void:
	_click(_by_mode(BattleSystem.AttackMode.MELEE))
	assert_eq(BattleSystem.AttackMode.MELEE, _battle.attack_mode)

	_player.stat_board.action_points.base_value = 0.0
	_ctl.player_can_act_changed.emit(_ctl.can_player_act())  # HudRoot's real gate path

	_click(_by_mode(BattleSystem.AttackMode.RANGED))

	assert_eq(_pressed_count(), 1)
	assert_eq(BattleSystem.AttackMode.MELEE, _battle.attack_mode,
			"the request must have been dropped (AP=0)")
	assert_eq(_lit_mode(), BattleSystem.AttackMode.MELEE,
			"the bar must not show Ranged as armed when the request never landed")


func test_click_during_is_launching_does_not_desync_the_bar() -> void:
	_click(_by_mode(BattleSystem.AttackMode.MELEE))
	assert_eq(BattleSystem.AttackMode.MELEE, _battle.attack_mode)

	# is_launching flips true with no signal of its own — the exact gap #464
	# lives in — so the bar is deliberately left ENABLED here, same as
	# production for the one frame between launch start and the swing's
	# post-await _reset().
	_battle.is_launching = true
	_click(_by_mode(BattleSystem.AttackMode.RANGED))

	assert_eq(_pressed_count(), 1)
	assert_eq(BattleSystem.AttackMode.MELEE, _battle.attack_mode,
			"the request must have been silently dropped (is_launching)")
	assert_eq(_lit_mode(), BattleSystem.AttackMode.MELEE,
			"REGRESSION: the bar must not show Ranged lit while Melee is still armed")
