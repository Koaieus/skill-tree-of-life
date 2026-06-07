## Inspector entry-point: appends a button to any selected StatBoard resource.
## Click → `visualize_requested` → `plugin.gd` shows the bottom panel.
@tool
extends EditorInspectorPlugin

signal visualize_requested(board: StatBoard)


func _can_handle(object: Object) -> bool:
	return object is StatBoard


func _parse_begin(object: Object) -> void:
	var board := object as StatBoard
	var btn := Button.new()
	btn.text = "  Open in StatBoard Visualizer"
	btn.icon = EditorInterface.get_editor_theme().get_icon(&"GraphEdit", &"EditorIcons")
	btn.tooltip_text = "Show this board in the bottom-panel graph (edges = intrinsic dependencies, rows = contributions)"
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void: visualize_requested.emit(board))
	add_custom_control(btn)
