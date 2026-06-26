class_name PlayerInputController
extends Node

## Routes player input (skill-node clicks + UI intent) on behalf of a single
## Player entity. Owns the gate: "is it this player's turn, and is the current
## phase one in which the requested action is legal?" Emits
## [signal player_can_act_changed] so UI can mirror enabled/disabled state.
##
## A single-player handler is enough for the MVP. Multi-entity selection
## (per-entity cores, hot-seat) would replace `player` with a selection
## strategy without changing the dispatch shape.

@export var graph: Graph
@export var allocation_system: AllocationSystem
@export var battle_system: BattleSystem
@export var player: Entity: set = _set_player
@export var turn_manager: TurnManager

signal player_can_act_changed(can_act: bool)
## Core-move targeting state (#21). `source` is the player's core node while a
## click-source-then-target move is in flight, or null when no move is being
## composed. Future highlight overlay subscribes here to paint CORE_LANDING /
## CORE_PATH roles.
signal core_move_targeting_changed(source: SkillNode)

## The player's core node while a click-to-move is in progress. Null between
## moves. Set only via `_set_move_targeting_source` so the signal fires once
## per transition.
var _move_targeting_source: SkillNode = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# `player` may be wired post-_ready (procgen sandboxes spawn it during
	# GameRoot._setup_level). Skip the player-dependent gate, not the graph
	# subscription — clicks still connect; routing checks player at fire time.
	if graph == null or allocation_system == null or turn_manager == null:
		push_warning("PlayerInputController missing graph/allocation/turn_manager; clicks won't route")
		return
	graph.node_added.connect(_on_node_added)
	for sn in graph.get_skill_nodes():
		_on_node_added(sn)

	turn_manager.phase_changed.connect(_emit_gate_changed.unbind(2))
	turn_manager.turn_started.connect(_emit_gate_changed.unbind(1))
	turn_manager.turn_ended.connect(_emit_gate_changed.unbind(1))


func _on_node_added(skill_node: SkillNode) -> void:
	if not skill_node.left_clicked.is_connected(_on_skill_node_left_clicked):
		skill_node.left_clicked.connect(_on_skill_node_left_clicked)
	if not skill_node.right_clicked.is_connected(_on_skill_node_right_clicked):
		skill_node.right_clicked.connect(_on_skill_node_right_clicked)


func _on_skill_node_left_clicked(skill_node: SkillNode) -> void:
	if _route_battle_click(skill_node, true):
		return
	if _route_core_move_click(skill_node):
		return
	if turn_manager.can_allocate() and skill_node.owned_by == null:
		allocation_system.allocate(skill_node, player)
	elif turn_manager.can_deallocate() and skill_node.owned_by == player:
		allocation_system.deallocate(skill_node, player)


func _on_skill_node_right_clicked(skill_node: SkillNode) -> void:
	_route_battle_click(skill_node, false)


## Returns true if a battle-phase plan handled the click. Gating: player's
## turn AND the active plan belongs to this player. Caller treats `true`
## as "consumed, no further routing".
func _route_battle_click(skill_node: SkillNode, is_left: bool) -> bool:
	if not can_player_act():
		return false
	if not battle_system.is_attacking:
		return false
	var plan := battle_system.attack_plan
	if plan == null or plan.attacker != player:
		return false
	if is_left:
		plan._on_node_left_clicked(skill_node)
	else:
		plan._on_node_right_clicked(skill_node)
	return true


## Core-movement (#21) click routing. Two-phase: first click on the player's
## own core enters targeting; second click on an adjacent owned node commits
## via `AllocationSystem.move_core`. Returns true when the click was consumed
## (don't fall through to allocate/deallocate). Phase gated to CONTRACT and
## EXPAND — BATTLE is reserved for the active attack plan.
##
## Rules:
##  - Not the player's turn, or BATTLE phase, or zero MP → no-op, fall through.
##    Active targeting state is cleared so a stale source can't outlive its
##    eligibility window.
##  - No source set + click on player.core_location → enter targeting.
##  - Source set + click on source → cancel targeting.
##  - Source set + click on any owned node → call move_core (succeeds for
##    adjacent, fails silently for non-adjacent) and clear targeting. Consumed
##    so a non-adjacent owned click in CONTRACT can't accidentally deallocate.
##  - Source set + click on unowned/enemy node → cancel targeting, fall through
##    so the player can still allocate in EXPAND.
func _route_core_move_click(skill_node: SkillNode) -> bool:
	if player == null or turn_manager == null or allocation_system == null:
		return false
	if turn_manager.current_entity != player:
		return false
	if turn_manager.current_phase == TurnManager.Phase.BATTLE:
		return false
	if not _player_has_movement_points():
		if _move_targeting_source != null:
			_set_move_targeting_source(null)
		return false

	if _move_targeting_source == null:
		if skill_node == player.core_location:
			_set_move_targeting_source(skill_node)
			return true
		return false

	# Targeting is active — this click is the target.
	if skill_node == _move_targeting_source:
		_set_move_targeting_source(null)
		return true
	if skill_node.owned_by == player:
		allocation_system.move_core(player, skill_node)
		_set_move_targeting_source(null)
		return true
	# Click on someone else's node / unowned: cancel and fall through so
	# allocate-in-EXPAND still works without a second click.
	_set_move_targeting_source(null)
	return false


func _player_has_movement_points() -> bool:
	if player == null or player.stat_board == null:
		return false
	var mp: PoolStat = player.stat_board.movement_points
	return mp != null and mp.current >= 1


func _set_move_targeting_source(value: SkillNode) -> void:
	if _move_targeting_source == value:
		return
	_move_targeting_source = value
	core_move_targeting_changed.emit(value)


func can_player_act() -> bool:
	if not (turn_manager.can_act() and turn_manager.current_entity == player):
		return false
	# AP=0 in BATTLE phase blocks further actions; UI uses this to dim.
	if player != null and player.stat_board != null:
		var ap: PoolStat = player.stat_board.action_points
		if ap != null and ap.current <= 0:
			return false
	return true


func on_attack_mode_requested(mode: BattleSystem.AttackMode) -> void:
	if can_player_act():
		battle_system.request_attack_mode(mode)


func _emit_gate_changed() -> void:
	player_can_act_changed.emit(can_player_act())


func _set_player(value: Entity) -> void:
	if player == value:
		return
	if player != null and player.stat_board != null:
		var prev_ap: PoolStat = player.stat_board.action_points
		if prev_ap != null and prev_ap.current_changed.is_connected(_on_ap_changed):
			prev_ap.current_changed.disconnect(_on_ap_changed)
	player = value
	if player != null and player.stat_board != null:
		var ap: PoolStat = player.stat_board.action_points
		if ap != null:
			ap.current_changed.connect(_on_ap_changed)


func _on_ap_changed(_new_current: Variant) -> void:
	_emit_gate_changed()
