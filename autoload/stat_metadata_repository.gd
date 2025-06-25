@tool
extends Node

var FALLBACK_METADATA: StatMetaData = preload('res://stat_system/metadata/fallback_metadata.tres')

@export var repository: Dictionary[GDScript, StatMetaData] = {}

@export_dir var stat_list_directory: String = "res://stats/list":
	get(): return stat_list_directory
	set(value):
		stat_list_directory = value
		populate_repository_keys()

@export_tool_button('Populate keys') var button = populate_repository_keys


func get_by_key(key: GDScript) -> StatMetaData:
	if not key:
		return null
	#print('F: %s %s %s' % [FALLBACK_METADATA, FALLBACK_METADATA.get_class(), typeof(FALLBACK_METADATA)])
	#return repository.get(key)
	return repository.get(key, FALLBACK_METADATA)

func populate_repository_keys():
	print('Populating Stat Metadata Repository...')
	var prev_repo_size: int = len(repository)
	for file in ResourceLoader.list_directory(stat_list_directory):
		if file.get_extension() != 'gd':
			continue
		var script: GDScript = load("%s/%s" % [stat_list_directory, file])
		if script is not GDScript:
			continue
		if script not in repository:
			repository[script] = StatMetaData.new()
	print('%s new entries added' % (len(repository) - prev_repo_size))
	notify_property_list_changed()
