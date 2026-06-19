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
@export var player: Entity
@export var turn_manager: TurnManager

signal player_can_act_changed(can_act: bool)


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
	if turn_manager.can_allocate():
		if skill_node.owned_by == null:
			allocation_system.allocate(skill_node, player)
		elif skill_node.owned_by == player:
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


func can_player_act() -> bool:
	return turn_manager.can_act() and turn_manager.current_entity == player


func on_attack_mode_requested(mode: BattleSystem.AttackMode) -> void:
	if can_player_act():
		battle_system.request_attack_mode(mode)


func _emit_gate_changed() -> void:
	player_can_act_changed.emit(can_player_act())
