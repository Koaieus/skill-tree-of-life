class_name OptionsMenuScreen
extends MenuScreen

## Wraps the existing [SettingsMenu] (which already builds its rows from
## GameSettings) rather than re-deriving an options UI.

const SETTINGS_MENU := preload("res://scenes/meta/settings_menu.tscn")


func _ready() -> void:
	super._ready()
	set_title("Options")
	var settings: Control = SETTINGS_MENU.instantiate()
	settings.custom_minimum_size = Vector2(0, 280)
	settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(settings)
