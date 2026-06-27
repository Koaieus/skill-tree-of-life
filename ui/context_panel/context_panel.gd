class_name ContextPanel
extends PanelContainer

## Center-right contextual surface. Replaces the old phase-keyed panel (phases
## were removed in #60): the body is now chosen by the player's CURRENT CONTEXT,
## resolved by priority, not by a turn phase.
##
##   active attack plan  >  core-move targeting  >  pinned node  >  idle
##
## Each context has its own pre-authored body scene (inherited from
## [ContextBodyBase]) swapped into [code]BodySlot[/code]. A pinned node persists
## in state but is temporarily overridden while an attack plan or core-move is
## active, then returns. New contexts = a new body scene + a branch in
## [method _compute_context]; the panel framework stays put.

const _ATTACK_BODY := preload("res://ui/context_panel/bodies/attack_plan_body.tscn")
const _CORE_MOVE_BODY := preload("res://ui/context_panel/bodies/core_move_body.tscn")
const _PINNED_BODY := preload("res://ui/context_panel/bodies/pinned_node_body.tscn")
const _IDLE_BODY := preload("res://ui/context_panel/bodies/idle_body.tscn")

enum Context { IDLE, ATTACK, CORE_MOVE, PINNED }

@onready var _header: Label = $Margin/VBox/Header
@onready var _body_slot: Control = $Margin/VBox/BodySlot

var _turn_manager: TurnManager
var _battle_system: BattleSystem
var _input_ctl: PlayerInputController
var _player: Entity

var _pinned_node: SkillNode = null
var _current: int = -1
var _current_node: SkillNode = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Injected by [UIRoot.compose]. Subscribes to the coarse signals that change
## which context is active (NOT per-tick state — the bodies self-subscribe to
## that for their own live previews).
func bind(turn_manager: TurnManager, battle_system: BattleSystem,
		input_ctl: PlayerInputController, player: Entity) -> void:
	_turn_manager = turn_manager
	_battle_system = battle_system
	_input_ctl = input_ctl
	_player = player
	if _battle_system != null:
		_battle_system.attack_plan_changed.connect(_on_context_changed.unbind(1))
	if _input_ctl != null:
		_input_ctl.core_move_targeting_changed.connect(_on_context_changed.unbind(1))
		_input_ctl.node_pinned.connect(_on_node_pinned)
	if _turn_manager != null:
		_turn_manager.turn_started.connect(_on_context_changed.unbind(1))
	_resolve()


func _on_node_pinned(node: SkillNode) -> void:
	_pinned_node = node
	_resolve()


func _on_context_changed() -> void:
	_resolve()


func _resolve() -> void:
	var ctx := _compute_context()
	var node := _context_node(ctx)
	if ctx == _current and node == _current_node:
		return
	_current = ctx
	_current_node = node
	_swap_body(ctx, node)


func _compute_context() -> int:
	if _battle_system != null and _battle_system.attack_plan != null:
		return Context.ATTACK
	if _input_ctl != null and _input_ctl.move_targeting_source() != null:
		return Context.CORE_MOVE
	if _pinned_node != null:
		return Context.PINNED
	return Context.IDLE


func _context_node(ctx: int) -> SkillNode:
	match ctx:
		Context.CORE_MOVE:
			return _input_ctl.move_targeting_source() if _input_ctl != null else null
		Context.PINNED:
			return _pinned_node
	return null


func _swap_body(ctx: int, node: SkillNode) -> void:
	if _body_slot == null:
		return
	for child in _body_slot.get_children():
		child.queue_free()
	_header.text = _title_for(ctx)
	var scene := _scene_for(ctx)
	if scene == null:
		return
	var body := scene.instantiate()
	_body_slot.add_child(body)
	if body is ContextBodyBase:
		(body as ContextBodyBase).bind(_player, _battle_system, _input_ctl, node)


func _scene_for(ctx: int) -> PackedScene:
	match ctx:
		Context.ATTACK: return _ATTACK_BODY
		Context.CORE_MOVE: return _CORE_MOVE_BODY
		Context.PINNED: return _PINNED_BODY
		Context.IDLE: return _IDLE_BODY
	return null


func _title_for(ctx: int) -> String:
	match ctx:
		Context.ATTACK: return "Attack"
		Context.CORE_MOVE: return "Move Core"
		Context.PINNED: return "Node"
		Context.IDLE: return "—"
	return "—"
