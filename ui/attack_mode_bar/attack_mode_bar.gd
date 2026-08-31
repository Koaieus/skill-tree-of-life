@tool
class_name AttackModeBar
extends HBoxContainer

signal attack_mode_requested(mode: BattleSystem.AttackMode)

const _PALETTE := preload("res://ui/theme/action_palette.tres")

@onready var _group: ButtonGroup = $MeleeToggleButton.button_group
@onready var _manage_button: AttackModeButton = $ManageToggleButton

## Mirrors whatever [method set_active_mode] was last told — NOT derived from
## button toggle state. Godot's [ButtonGroup] radio-exclusivity silently
## blocks un-pressing the already-active button on re-click, so we listen to
## each button's raw `pressed` (fires on every click, toggle-state-change or
## not) rather than the group's `pressed`/`toggled` signals, and decide
## cancel-vs-switch ourselves against this tracked value.
var _active_mode: BattleSystem.AttackMode = BattleSystem.AttackMode.NONE


func _ready() -> void:
	for btn: AttackModeButton in _group.get_buttons():
		btn.pressed.connect(_on_button_pressed.bind(btn))

	# Manage has no attribute behind it, so unlike Melee/Ranged/Magic (which
	# resolve their own tint from StatDef in AttackModeButton._resolve_tint)
	# it is a deliberate second source (#669): the shared ActionPalette's
	# `&"manage"` surface key.
	_manage_button.tint = _PALETTE.color_for(&"manage")


## Re-clicking the already-active Melee/Ranged/Magic tab cancels back to
## Manage instead of doing nothing (the ButtonGroup default). Manage itself
## has no "active mode" to cancel out of, so it always just (re)requests NONE.
func _on_button_pressed(btn: AttackModeButton) -> void:
	var mode := btn.attack_mode
	if mode == _active_mode and mode != BattleSystem.AttackMode.NONE:
		attack_mode_requested.emit(BattleSystem.AttackMode.NONE)
	else:
		attack_mode_requested.emit(mode)


func set_active_mode(mode: BattleSystem.AttackMode) -> void:
	_active_mode = mode
	for btn: AttackModeButton in _group.get_buttons():
		btn.override_toggle(btn.attack_mode == mode)

func set_enabled(enabled: bool) -> void:
	for btn: AttackModeButton in _group.get_buttons():
		btn.enabled = enabled
	tooltip_text = "" if enabled else "Not your turn, or no action points remaining"
