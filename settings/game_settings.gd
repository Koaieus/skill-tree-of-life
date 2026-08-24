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

enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }

## Indexed by the `resolution` export below; keep the two in lockstep.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

@export_group("Audio")
@export_range(0.0, 1.0) var master_volume: float = 0.8

@export_group("Gameplay")
@export var confirm_islanding_dealloc: bool = true
@export_range(0.0, 2.0) var ai_turn_delay: float = 0.4
## Skip presentation-layer transitions and land on their end state in one
## frame — the frontmatter's camera move and grow-in (#570), and anything that
## follows it. An accessibility setting, sitting beside `ai_turn_delay` because
## both are about how much motion the player sits through rather than about a
## rule. Every animated unit honours it by jumping to `set_progress(1.0)`; none
## of them branch further than that.
@export var reduce_motion: bool = false

@export_group("Display")
@export_enum("Windowed", "Fullscreen", "Borderless") var window_mode: int = WindowMode.WINDOWED
@export_enum("1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160") var resolution: int = 2
@export_enum("Disabled", "Enabled", "Adaptive") var vsync_mode: int = DisplayServer.VSYNC_ENABLED
## 0 = uncapped.
@export_range(0, 300, 1) var max_fps: int = 0
