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
	if graph == null or allocation_system == null or player == null:
		push_warning("PlayerInputController missing a reference; clicks won't route")
		return
	graph.node_added.connect(_on_node_added)
	for sn in graph.get_skill_nodes():
		_on_node_added(sn)

	turn_manager.phase_changed.connect(_emit_gate_changed.unbind(2))
	turn_manager.turn_started.connect(_emit_gate_changed.unbind(1))
	turn_manager.turn_ended.connect(_emit_gate_changed.unbind(1))


func _on_node_added(skill_node: SkillNode) -> void:
	if not skill_node.clicked.is_connected(_on_skill_node_clicked):
		skill_node.clicked.connect(_on_skill_node_clicked)


func _on_skill_node_clicked(skill_node: SkillNode) -> void:
	if turn_manager.can_allocate():
		if skill_node.owned_by == null:
			allocation_system.allocate(skill_node, player)
		elif skill_node.owned_by == player:
			allocation_system.deallocate(skill_node, player)


func can_player_act() -> bool:
	return turn_manager.can_act() and turn_manager.current_entity == player


func on_attack_mode_requested(mode: BattleSystem.AttackMode) -> void:
	if can_player_act():
		battle_system.request_attack_mode(mode)


func _emit_gate_changed() -> void:
	player_can_act_changed.emit(can_player_act())
