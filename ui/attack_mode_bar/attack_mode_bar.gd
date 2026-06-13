@tool
class_name AttackModeBar
extends HBoxContainer

signal attack_mode_requested(mode: BattleSystem.AttackMode)

@onready var _group: ButtonGroup = $MeleeToggleButton.button_group


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_group.pressed.connect(_on_group_pressed)
	for btn in _group.get_buttons():
		(btn as Button).toggled.connect(_on_any_toggled)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_group_pressed(button: BaseButton) -> void:
	attack_mode_requested.emit((button as AttackModeButton).attack_mode)

func _on_any_toggled(toggled_on: bool) -> void:
	if not toggled_on and _group.get_pressed_button() == null:
		attack_mode_requested.emit(BattleSystem.AttackMode.NONE)

func set_active_mode(mode: BattleSystem.AttackMode) -> void:
	for btn: AttackModeButton in _group.get_buttons():
		btn.override_toggle(btn.attack_mode == mode)

func set_enabled(enabled: bool) -> void:
	for btn: AttackModeButton in _group.get_buttons():
		btn.enabled = enabled
