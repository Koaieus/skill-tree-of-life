class_name HighlightController
extends Node

## Single source of truth for which [HighlightProvider] is currently driving the
## highlight overlays. Only ONE provider is active at a time — there's a natural
## priority among the things that want to highlight, and stacking two would just
## read as noise. The overlays ([NodeHighlightOverlay], [EdgeHighlightOverlay])
## subscribe here, not to each provider, so a new highlight source is wired by
## teaching this resolver about it — the overlays never change.
##
## Priority (highest first): active attack plan > core-move targeting > none.
## Mirrors the ContextPanel resolver deliberately — same shape, different output.
##
## A scene-tree system (sibling of the other Systems nodes). Its system deps are
## NodePath @exports wired in game_root.tscn — same DI style as AllocationSystem
## / PlayerInputController — so they're resolved before `_ready` and the signal
## wiring lives there. Joins [constant GROUP] for discovery.

const GROUP := &"highlight_controller"

## Fires when the active provider is swapped (incl. to/from null).
signal provider_changed(provider: HighlightProvider)
## Fires when the active provider mutates internally (target picked, drag moved)
## without a swap. Overlays repaint on both.
signal provider_state_changed

# Scene-wired deps (NodePath @exports — see game_root.tscn).
@export var battle_system: BattleSystem
@export var input_ctl: PlayerInputController
@export var allocation_system: AllocationSystem
@export var graph: Graph
## The entity whose core moves (the human player) — fallback when a core node's
## owner can't be read. Set by GameRoot once the player resolves (it's spawned at
## runtime, so it can't be a scene NodePath); only read during a live core-move.
var player: Entity

## The active provider. Setter rebinds its [signal HighlightProvider.state_changed]
## so internal mutations re-emit as [signal provider_state_changed].
var provider: HighlightProvider = null:
	set = _set_provider

# Reused across core-move sessions so we don't churn instances every drag.
var _core_provider: CoreMoveHighlightProvider = null


func _enter_tree() -> void:
	add_to_group(GROUP)


## Wire to the systems whose state drives provider selection, then pick the
## initial provider. Deps are scene-injected via NodePath @exports, so they're
## populated by the time `_ready` runs.
func _ready() -> void:
	if battle_system != null:
		battle_system.attack_plan_changed.connect(_on_source_changed.unbind(1))
	if input_ctl != null:
		input_ctl.core_move_targeting_changed.connect(_on_source_changed.unbind(1))
	_resolve()


func _on_source_changed() -> void:
	_resolve()


## Pick the active provider by priority and install it (the setter handles
## rebinding + the provider_changed emit).
func _resolve() -> void:
	var next: HighlightProvider = null
	if battle_system != null and battle_system.attack_plan != null:
		next = battle_system.attack_plan
	elif input_ctl != null and input_ctl.move_targeting_source() != null:
		next = _build_core_provider()
	provider = next


func _build_core_provider() -> CoreMoveHighlightProvider:
	var src := input_ctl.move_targeting_source()
	var entity: Entity = src.owned_by if src != null and src.owned_by != null else player
	var budget := 0
	if entity != null and entity.stat_board != null and entity.stat_board.movement_points != null:
		budget = int(entity.stat_board.movement_points.current)
	var reach: Dictionary = {}
	if allocation_system != null and entity != null:
		reach = allocation_system.reachable_core_landings(entity, budget)
	if _core_provider == null:
		_core_provider = CoreMoveHighlightProvider.new()
	_core_provider.configure(src, reach, graph)
	return _core_provider


## Read the active core-move provider (if core-move is the active driver) so the
## input controller can push drag-target previews into it. Null otherwise.
func active_core_provider() -> CoreMoveHighlightProvider:
	return provider as CoreMoveHighlightProvider


func _set_provider(value: HighlightProvider) -> void:
	if provider == value:
		return
	if provider != null and provider.state_changed.is_connected(_on_provider_state_changed):
		provider.state_changed.disconnect(_on_provider_state_changed)
	provider = value
	if provider != null and not provider.state_changed.is_connected(_on_provider_state_changed):
		provider.state_changed.connect(_on_provider_state_changed)
	provider_changed.emit(provider)


func _on_provider_state_changed() -> void:
	provider_state_changed.emit()
