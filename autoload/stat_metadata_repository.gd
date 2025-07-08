@tool
extends Node


## Mapping of class names to StatMetaData resources
@export var repository: Dictionary[StringName, StatMetaData] = {}

## Button to manually trigger population
@export_tool_button('Populate keys') var button = _populate_missing_entries.bind(true)

#@export_tool_button("Save Repository") var save_button = _save_repository

## Fallback metadata to use when no stat class was found/configured
var FALLBACK_METADATA: StatMetaData = preload('res://stat_system/metadata/fallback_metadata.tres')

func _ready():
	if Engine.is_editor_hint():
		_populate_missing_entries()
	else:
		_validate_runtime_repository()

#region Public API
## Get metadata by class name string
func get_by_class_name(_name: String) -> StatMetaData:
	return repository.get(_name, FALLBACK_METADATA)

## Resolve metadata for stat instance by its class name
func get_for_stat(stat: Stat) -> StatMetaData:
	var cls: String = stat.get_script().get_global_name()
	return get_by_class_name(cls) if cls else FALLBACK_METADATA

## Metadata lookup using the .gd script object
func get_by_key(key: GDScript) -> StatMetaData:
	assert(key, "StatMetaDataRepository.get_by_key() called with null key!")
	return repository.get(key.resource_path, FALLBACK_METADATA)
#endregion


## Only adds missing entries; does not overwrite
func _populate_missing_entries(refresh_cache: bool = false):
	if refresh_cache:
		_list_of_stat_classes.clear()
	var previous_num_entries: int = repository.size()
	for cls_name in _list_of_stat_classes:
		if not repository.has(cls_name):
			repository[cls_name] = StatMetaData.new()
	var num_added_entries: int = repository.size() - previous_num_entries
	notify_property_list_changed()
	if num_added_entries:
		print("🗂️ StatMetaDataRepository: Added %s missing entries." % num_added_entries)
	else:
		print("🗂️ StatMetaDataRepository: Nothing to populate, already up to date")

## Runtime warning validation
func _validate_runtime_repository():
	for warning in _get_configuration_warnings():
		push_warning(warning)

var _list_of_stat_classes: Array[StringName]:
	get():
		if not _list_of_stat_classes:
			_list_of_stat_classes = _get_list_of_stat_classes()
		return _list_of_stat_classes

func _get_list_of_stat_classes() -> Array[StringName]:
	var project_settings = ProjectSettings.get_global_class_list()
	var result: Array[StringName] = []
	var base_map := {}

	# Make initial map of class_name ⇒ base
	for entry in project_settings:
		if not entry.has("class") or not entry.has("base"):
			continue
		base_map[entry.class] = entry.base

	# Track path we go down (for shortcutting)
	var rabbit_hole: Array[StringName] = []
	var is_descendant_of_stat = func(cls: StringName) -> bool:
		rabbit_hole.clear()
		while cls in base_map:
			print('Checking %s...' % cls)
			cls = base_map[cls]
			if cls == "Stat":
				return true
			rabbit_hole.append(cls)
		return false

	for entry in project_settings:
		if entry.path.get_file().begins_with("_"):
			continue
		if is_descendant_of_stat.call(entry.class):
			for rabbit in rabbit_hole:
				# Shortcut: Update base map along the way down to here
				base_map[rabbit] = "Stat" 
			# Save this precious result
			result.append(entry.class)
	return result


## Provides inspector-visible configuration warnings
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if repository.is_empty():
		warnings.append("StatMetaDataRepository: repository is empty—click 'Populate' or assign StatMetaData manually.")
		return warnings
	
	for key in repository.keys():
		if not _list_of_stat_classes.has(key):
			warnings.append("StatMetaDataRepository: class '%s' no longer exists or has changed class_name." % key)
		elif repository[key] == null:
			warnings.append("StatMetaDataRepository: class '%s' entry is missing StatMetaData." % key)
	for cls_name in ClassDB.get_class_list():
		if cls_name.begins_with("_"):
			continue
		if not ClassDB.is_parent_class(cls_name, "Stat"):
			continue
		if not repository.has(cls_name):
			warnings.append("StatMetaDataRepository: missing metadata entry for class '%s'." % cls_name)
	return warnings


#func _save_repository():
	#var error: Error = ResourceSaver.save(self, "res://stat_metadata.tres")
	#if error != OK:
		#push_error("Failed to save StatMetaDataRepository: %s" % error)
	#else:
		#print("✅ Repository saved to %s" % scene_file_path)
