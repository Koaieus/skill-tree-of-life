@tool
extends EditorPlugin

## Mounts an inspector plugin that injects a heatmap preview into the
## inspector header whenever a [GraphProcgenConfig] is selected.

const _InspectorPlugin := preload("res://addons/procgen_preview/inspector_plugin.gd")

var _inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector_plugin = _InspectorPlugin.new()
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
