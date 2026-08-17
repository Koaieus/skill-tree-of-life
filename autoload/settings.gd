extends Node

## Live GameSettings instance, persisted to user://settings.cfg. Reflects
## GameSettings.get_property_list() rather than hand-listing keys, so the
## menu/persistence/this autoload never drift from the class.

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

signal changed(key: StringName, value: Variant)

var current: GameSettings = GameSettings.new()


func _ready() -> void:
	load_settings()


func set_value(key: StringName, value: Variant) -> void:
	current.set(key, value)
	changed.emit(key, value)


func get_value(key: StringName) -> Variant:
	return current.get(key)


## Exported, storable properties only — drops @export_group/@export_category
## markers and any script-internal noise get_property_list() may report.
func exported_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for prop in current.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		keys.append(StringName(prop.name))
	return keys


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in exported_keys():
		cfg.set_value(SECTION, key, current.get(key))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("Settings.save_settings: failed to save %s: %s" % [SAVE_PATH, err])


## Stored keys that no longer exist on GameSettings are dropped silently —
## that's the whole point of a typed Resource over a StringName registry:
## retirement is exhaustive at compile time, not a runtime lookup miss.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	if not cfg.has_section(SECTION):
		return
	var valid_keys := exported_keys()
	for key in cfg.get_section_keys(SECTION):
		if not valid_keys.has(StringName(key)):
			continue
		current.set(key, cfg.get_value(SECTION, key))
