extends GutTest

const SAVE_PATH := "user://settings.cfg"

var _had_previous_file := false
var _backup: PackedByteArray


func before_each() -> void:
	_had_previous_file = FileAccess.file_exists(SAVE_PATH)
	if _had_previous_file:
		_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
	Settings.current = GameSettings.new()


func after_each() -> void:
	if _had_previous_file:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	Settings.current = GameSettings.new()


func test_round_trips_every_exported_property_through_config_file() -> void:
	Settings.current.master_volume = 0.42
	Settings.current.confirm_islanding_dealloc = false
	Settings.current.ai_turn_delay = 1.25
	Settings.current.window_mode = GameSettings.WindowMode.BORDERLESS
	Settings.current.resolution = 3
	Settings.current.vsync_mode = DisplayServer.VSYNC_ADAPTIVE
	Settings.current.max_fps = 144

	Settings.save_settings()
	Settings.current = GameSettings.new()
	Settings.load_settings()

	assert_almost_eq(Settings.current.master_volume, 0.42, 0.0001)
	assert_eq(Settings.current.confirm_islanding_dealloc, false)
	assert_almost_eq(Settings.current.ai_turn_delay, 1.25, 0.0001)
	assert_eq(Settings.current.window_mode, GameSettings.WindowMode.BORDERLESS)
	assert_eq(Settings.current.resolution, 3)
	assert_eq(Settings.current.vsync_mode, DisplayServer.VSYNC_ADAPTIVE)
	assert_eq(Settings.current.max_fps, 144)


func test_setting_a_display_key_does_not_crash_headless() -> void:
	Settings.set_value(&"window_mode", GameSettings.WindowMode.FULLSCREEN)
	Settings.set_value(&"resolution", 0)
	Settings.set_value(&"vsync_mode", DisplayServer.VSYNC_DISABLED)
	Settings.set_value(&"max_fps", 60)

	assert_eq(Settings.current.max_fps, 60)


func test_retired_setting_in_cfg_is_dropped_not_crashed() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "master_volume", 0.5)
	cfg.set_value("settings", "some_retired_setting_that_no_longer_exists", "legacy")
	cfg.save(SAVE_PATH)

	Settings.current = GameSettings.new()
	Settings.load_settings()

	assert_almost_eq(Settings.current.master_volume, 0.5, 0.0001)
	assert_null(Settings.current.get("some_retired_setting_that_no_longer_exists"))


## The autoload's defaults come from the authored res://settings/default_settings.tres,
## copied — never the resource-cache object itself, which load_settings() would
## otherwise mutate for the whole process on the first cfg read.
func test_fresh_autoload_copies_authored_defaults() -> void:
	var defaults: GameSettings = load("res://settings/default_settings.tres")
	var original_delay: float = defaults.ai_turn_delay
	defaults.ai_turn_delay = original_delay + 0.7
	var fresh = load("res://autoload/settings.gd").new()
	defaults.ai_turn_delay = original_delay

	assert_ne(fresh.current, defaults, "current must be a copy, not the cached resource")
	assert_almost_eq(fresh.current.ai_turn_delay, original_delay + 0.7, 0.0001,
		"a fresh autoload must read the authored .tres, not GameSettings.new()")
	for key in fresh.exported_keys():
		if key == &"ai_turn_delay":
			continue
		assert_eq(fresh.current.get(key), defaults.get(key), "default for %s" % key)
	fresh.free()
