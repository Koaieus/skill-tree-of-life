@tool
extends Node

const DisplayType = StatMetaData.DisplayType

@export var widget_defaults: Dictionary[DisplayType, PackedScene] = {
	DisplayType.BASIC: preload("res://ui/widgets/stat/basic_stat_widget.tscn"),
	DisplayType.BAR: preload("res://ui/widgets/stat/bar_stat_widget.tscn"),
	DisplayType.PROGRESS_WITH_LABEL: preload("res://ui/widgets/stat/progress_bar_stat_widget.tscn"),
	DisplayType.INLINE: preload("res://ui/widgets/stat/inline_stat_widget.tscn"),
}



func _get_configuration_warnings() -> PackedStringArray:
	var arr = PackedStringArray() 
	for t in StatMetaData.DisplayType.values():
		if not widget_defaults.get(t):
			arr.append('Missing configuration for default widget for `%s`' % [StatMetaData.DisplayType.find_key(t)])
	return arr
