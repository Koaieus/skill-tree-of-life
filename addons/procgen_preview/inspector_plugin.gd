@tool
extends EditorInspectorPlugin

const _PreviewControl := preload("res://addons/procgen_preview/preview_control.gd")


func _can_handle(object: Object) -> bool:
	return object is GraphProcgenConfig


func _parse_begin(object: Object) -> void:
	var preview := _PreviewControl.new()
	preview.set_config(object as GraphProcgenConfig)
	add_custom_control(preview)
