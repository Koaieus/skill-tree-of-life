class_name PhaseContextPanel
extends PanelContainer

## Center-right contextual surface. Header names the active phase; the body
## slot swaps a phase-specific scene per [TurnManager.Phase]. Each body is
## its own .tscn (editor-previewable) and self-subscribes to the systems it
## needs — UIRoot just hands references via [method bind].

const _CONTRACT_BODY := preload("res://ui/phase_context_panel/bodies/contract_phase_body.tscn")
const _EXPAND_BODY := preload("res://ui/phase_context_panel/bodies/expand_phase_body.tscn")
const _BATTLE_BODY := preload("res://ui/phase_context_panel/bodies/battle_phase_body.tscn")

@onready var _header: Label = $Margin/VBox/Header
@onready var _body_slot: Control = $Margin/VBox/BodySlot

var _turn_manager: TurnManager
var _battle_system: BattleSystem
var _entity: Entity = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind(turn_manager: TurnManager, battle_system: BattleSystem) -> void:
	_turn_manager = turn_manager
	_battle_system = battle_system
	if _turn_manager != null:
		_turn_manager.phase_changed.connect(_on_phase_changed)
		_turn_manager.turn_started.connect(_on_turn_started)
		if _turn_manager.current_entity != null:
			_entity = _turn_manager.current_entity
			_on_phase_changed(_entity, _turn_manager.current_phase)


func _on_turn_started(entity: Entity) -> void:
	_entity = entity
	# phase_changed fires immediately after turn_started — body rebuild lives
	# there so we don't double-instantiate.


func _on_phase_changed(entity: Entity, phase: int) -> void:
	_entity = entity
	_header.text = _phase_name(phase)
	_swap_body(_scene_for_phase(phase))


func _scene_for_phase(phase: int) -> PackedScene:
	match phase:
		TurnManager.Phase.CONTRACT: return _CONTRACT_BODY
		TurnManager.Phase.EXPAND:   return _EXPAND_BODY
		TurnManager.Phase.BATTLE:   return _BATTLE_BODY
	return null


func _swap_body(scene: PackedScene) -> void:
	for child in _body_slot.get_children():
		child.queue_free()
	if scene == null:
		return
	var body := scene.instantiate()
	_body_slot.add_child(body)
	if body is PhaseBodyBase:
		(body as PhaseBodyBase).bind(_entity, _battle_system)


func _phase_name(phase: int) -> String:
	match phase:
		TurnManager.Phase.CONTRACT: return "Contraction"
		TurnManager.Phase.EXPAND: return "Expansion"
		TurnManager.Phase.BATTLE: return "Battle"
	return "—"
