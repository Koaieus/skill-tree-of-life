@tool
class_name AttackModeBar
extends HBoxContainer

signal attack_mode_requested(mode: BattleSystem.AttackMode)

@onready var _group: ButtonGroup = $MeleeToggleButton.button_group


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for btn: AttackModeButton in _group.get_buttons():
		btn.toggled.connect(_on_button_toggled, CONNECT_APPEND_SOURCE_OBJECT)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_toggled(toggled: bool, button: AttackModeButton) -> void:
	if toggled:
		attack_mode_requested.emit(button.attack_mode)
	


func set_active_mode(mode: BattleSystem.AttackMode) -> void:
	for btn: AttackModeButton in _group.get_buttons():
		btn.override_toggle(btn.mode == mode)

func set_enabled(enabled: bool) -> void:
	for btn: AttackModeButton in _group.get_buttons(): 
		btn._set_disabled(not enabled)
