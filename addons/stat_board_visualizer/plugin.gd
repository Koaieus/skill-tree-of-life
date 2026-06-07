## EditorPlugin: mounts a `StatBoardGraph` in the bottom panel and an
## `EditorInspectorPlugin` that adds an "Open in StatBoard Visualizer"
## button whenever a StatBoard resource is selected.
##
## Flow:
##   1. Inspector shows a StatBoard → InspectorPlugin appends a Button.
##   2. User clicks → InspectorPlugin emits `visualize_requested(board)`.
##   3. This plugin loads the board into the graph and reveals the panel.
@tool
extends EditorPlugin

const _BOTTOM_PANEL_TITLE := "StatBoard"
const _GRAPH_SCENE := preload("res://addons/stat_board_visualizer/stat_board_graph.tscn")

var _graph: Control  # StatBoardGraph instance
var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "StatBoardGraph"
	add_control_to_bottom_panel(_graph, _BOTTOM_PANEL_TITLE)

	_inspector = load("res://addons/stat_board_visualizer/stat_board_inspector.gd").new()
	_inspector.visualize_requested.connect(_on_visualize_requested)
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	if is_instance_valid(_graph):
		remove_control_from_bottom_panel(_graph)
		_graph.queue_free()
	if is_instance_valid(_inspector):
		remove_inspector_plugin(_inspector)


func _on_visualize_requested(board: StatBoard) -> void:
	_graph.call(&"load_board", board)
	make_bottom_panel_item_visible(_graph)
