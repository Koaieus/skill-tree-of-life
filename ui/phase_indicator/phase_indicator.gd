class_name PhaseIndicator
extends Control

## Center-top stylised label showing the active turn phase
## (CONTRACT / EXPAND / BATTLE). Slides down from the viewport edge each
## phase transition so the player gets a peripheral cue without it stealing
## focus. Visual treatment mirrors [Banner]'s PHASE style so the two read
## as a family.

@export_range(0.01, 1.0, 0.01) var slide_down_time: float = 0.22
@export_range(0.01, 0.5, 0.01)  var settle_time: float = 0.08

const _PHASE_NAMES: Dictionary[int, String] = {
	TurnManager.Phase.CONTRACT: "CONTRACT",
	TurnManager.Phase.EXPAND: "EXPAND",
	TurnManager.Phase.BATTLE: "BATTLE",
}
const _PHASE_TINTS: Dictionary[int, Color] = {
	TurnManager.Phase.CONTRACT: Color(0.75, 0.65, 1.0),
	TurnManager.Phase.EXPAND: Color(0.55, 1.0, 0.75),
	TurnManager.Phase.BATTLE: Color(1.0, 0.55, 0.55),
}

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Label

var _turn_manager: TurnManager
var _tween: Tween
var _resting_y: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 32)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	# Hide until a phase is set — keeps the slot from rendering an empty bar
	# before the first turn starts.
	_panel.modulate.a = 0.0


## UIRoot calls this once both subtrees are loaded. Subscribes to phase changes
## and snaps to current state if a turn is already in progress.
func bind(turn_manager: TurnManager) -> void:
	if _turn_manager == turn_manager:
		return
	if _turn_manager != null and _turn_manager.phase_changed.is_connected(_on_phase_changed):
		_turn_manager.phase_changed.disconnect(_on_phase_changed)
	_turn_manager = turn_manager
	if _turn_manager == null:
		return
	_turn_manager.phase_changed.connect(_on_phase_changed)
	if _turn_manager.current_entity != null:
		_on_phase_changed(_turn_manager.current_entity, _turn_manager.current_phase)


func _on_phase_changed(_entity: Entity, phase: int) -> void:
	_label.text = _PHASE_NAMES.get(phase, "—")
	var tint: Color = _PHASE_TINTS.get(phase, Color.WHITE)
	_label.add_theme_color_override("font_color", tint)
	_play_drop_in()


func _play_drop_in() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	# Drop from above viewport edge to resting position. Resting position is
	# captured the first time we animate so the scene can place the panel
	# wherever (we only need the delta back from that).
	if is_equal_approx(_resting_y, 0.0):
		_resting_y = _panel.position.y
	_panel.position.y = _resting_y - _panel.size.y - 12.0
	_panel.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "position:y", _resting_y, slide_down_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate:a", 1.0, settle_time)
