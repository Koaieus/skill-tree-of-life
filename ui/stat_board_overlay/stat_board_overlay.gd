## Runtime debug overlay: F3 toggles a StatBoardGraph over the game.
##
## Wire by the scene glue (HudRoot.rebind_player does this):
##   stat_board_overlay.board = board
##
## Mount: authored as a child of HudRoot in hud_root.tscn.
## The internal StatBoardGraph runs a 4 Hz refresh timer; we don't need to
## drive it from _process.
extends Control
class_name StatBoardOverlay

## Backdrop, StatBoardGraph and header, authored together.
const _CONTENT := preload("res://ui/stat_board_overlay/stat_board_overlay_content.tscn")

## Wired by the enclosing scene.  Set before F3 is first pressed.
var board: StatBoard = null

var _graph: GraphEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var content := _CONTENT.instantiate() as Control
	add_child(content)
	_graph = content.get_node(^"%Graph") as GraphEdit

	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo:
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if visible:
		hide()
	else:
		_open()


func _open() -> void:
	if board == null:
		push_warning("StatBoardOverlay: no board — HudRoot.rebind_player has not set overlay.board yet")
		return
	_graph.call(&"load_board", board)
	show()
