class_name GameSettings
extends Resource

## Every player-facing setting, as real typed @exports — deliberately NOT a
## StringName registry (stats earn one because stat identity is genuinely
## runtime-dynamic; every settings read site knows the name at author time).
## Retiring a setting here means every call site fails to compile, loud and
## exhaustive, instead of a registry lookup silently returning null forever.
##
## get_property_list() walk (@export_group -> sections, hint/hint_string ->
## widget) drives both the reflected settings menu and ConfigFile
## persistence — one source of truth, written once.

@export_group("Audio")
@export_range(0.0, 1.0) var master_volume: float = 0.8

@export_group("Gameplay")
@export var confirm_islanding_dealloc: bool = true
@export_range(0.0, 2.0) var ai_turn_delay: float = 0.4
