class_name PhaseIndicator
extends Control

## Center-top phase breadcrumbs: [CONTRACT] → [EXPAND] → [BATTLE]. The active
## chip lights up in its canonical phase tint; the others stay muted. Visible
## only on the player's turn — on AI turns the row collapses to a small
## "awaiting opponents…" pulse so the player knows the loop is alive without
## being told the AI's business.
##
## Canonical phase tints are duplicated in [EndTurnButton.PHASE_TINTS]; keep
## the two in sync until they're hoisted to a shared resource.

const _PHASE_TINTS: Dictionary[int, Color] = {
	TurnManager.Phase.CONTRACT: Color(0.55, 0.70, 1.00),
	TurnManager.Phase.EXPAND:   Color(0.45, 1.00, 0.55),
	TurnManager.Phase.BATTLE:   Color(1.00, 0.55, 0.20),
}
const _MUTED_TINT := Color(0.55, 0.58, 0.65)
const _BG_ACTIVE := Color(0.12, 0.16, 0.22, 0.92)
const _BG_MUTED  := Color(0.07, 0.09, 0.14, 0.55)
const _BORDER_MUTED := Color(0.35, 0.40, 0.48, 0.55)

@onready var _breadcrumbs: HBoxContainer = $Breadcrumbs
@onready var _awaiting: Label = $Awaiting

@onready var _chips: Dictionary[int, Control] = {
	TurnManager.Phase.CONTRACT: $Breadcrumbs/ChipContract,
	TurnManager.Phase.EXPAND:   $Breadcrumbs/ChipExpand,
	TurnManager.Phase.BATTLE:   $Breadcrumbs/ChipBattle,
}
@onready var _chip_labels: Dictionary[int, Label] = {
	TurnManager.Phase.CONTRACT: $Breadcrumbs/ChipContract/Margin/Label,
	TurnManager.Phase.EXPAND:   $Breadcrumbs/ChipExpand/Margin/Label,
	TurnManager.Phase.BATTLE:   $Breadcrumbs/ChipBattle/Margin/Label,
}

var _turn_manager: TurnManager
var _player: Entity
var _awaiting_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pre-render at muted; first phase_changed will paint the active one.
	for phase in _chips.keys():
		_paint_chip(phase, false)


## UIRoot calls this once both subtrees are loaded. Binds to phase / turn
## changes and snaps to current state.
func bind(turn_manager: TurnManager, player: Entity) -> void:
	_player = player
	if _turn_manager == turn_manager:
		_refresh()
		return
	if _turn_manager != null:
		if _turn_manager.phase_changed.is_connected(_on_phase_changed):
			_turn_manager.phase_changed.disconnect(_on_phase_changed)
		if _turn_manager.turn_started.is_connected(_on_turn_event):
			_turn_manager.turn_started.disconnect(_on_turn_event)
	_turn_manager = turn_manager
	if _turn_manager == null:
		return
	_turn_manager.phase_changed.connect(_on_phase_changed)
	_turn_manager.turn_started.connect(_on_turn_event)
	_refresh()


func _on_phase_changed(_entity: Entity, _phase: int) -> void:
	_refresh()


func _on_turn_event(_entity: Entity) -> void:
	_refresh()


func _refresh() -> void:
	if _turn_manager == null:
		return
	var is_player_turn := _player != null and _turn_manager.current_entity == _player
	_breadcrumbs.visible = is_player_turn
	_awaiting.visible = not is_player_turn
	if is_player_turn:
		var active_phase := _turn_manager.current_phase
		for phase in _chips.keys():
			_paint_chip(phase, phase == active_phase)
		_stop_awaiting_pulse()
	else:
		_start_awaiting_pulse()


func _paint_chip(phase: int, is_active: bool) -> void:
	var chip: Control = _chips.get(phase)
	if chip == null:
		return
	var label: Label = _chip_labels.get(phase)
	var style: StyleBoxFlat = chip.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	# StyleBoxes from .tscn are shared across instances unless we duplicate. We
	# only ever have one PhaseIndicator at a time so a per-call duplicate would
	# be wasteful — but the chips share the same source style by default, so
	# the first paint must duplicate-per-chip. Cheap: do it once and stash.
	if not chip.has_meta("style_owned"):
		style = style.duplicate() as StyleBoxFlat
		chip.add_theme_stylebox_override("panel", style)
		chip.set_meta("style_owned", true)
	if is_active:
		var tint: Color = _PHASE_TINTS.get(phase, Color.WHITE)
		style.bg_color = _BG_ACTIVE
		style.border_color = Color(tint.r, tint.g, tint.b, 0.9)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		if label != null:
			label.add_theme_color_override("font_color", tint)
	else:
		style.bg_color = _BG_MUTED
		style.border_color = _BORDER_MUTED
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		if label != null:
			label.add_theme_color_override("font_color", _MUTED_TINT)


func _start_awaiting_pulse() -> void:
	if _awaiting_tween != null and _awaiting_tween.is_valid():
		return
	_awaiting.modulate.a = 0.55
	_awaiting_tween = create_tween().set_loops()
	_awaiting_tween.tween_property(_awaiting, "modulate:a", 1.0, 0.9)
	_awaiting_tween.tween_property(_awaiting, "modulate:a", 0.55, 0.9)


func _stop_awaiting_pulse() -> void:
	if _awaiting_tween != null and _awaiting_tween.is_valid():
		_awaiting_tween.kill()
	_awaiting_tween = null
	_awaiting.modulate.a = 1.0
