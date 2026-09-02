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

const StatBoardGraphScene := preload("res://addons/stat_board_visualizer/stat_board_graph.tscn")

## Wired by the enclosing scene.  Set before F3 is first pressed.
var board: StatBoard = null

var _graph: GraphEdit
var _bg: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.05, 0.05, 0.08, 0.55)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_graph = StatBoardGraphScene.instantiate()
	_graph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_graph.offset_left = 24
	_graph.offset_right = -24
	_graph.offset_top = 48
	_graph.offset_bottom = -24
	add_child(_graph)

	var header := Label.new()
	header.text = "StatBoard  ·  F3 to close"
	header.add_theme_font_size_override(&"font_size", 14)
	header.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.9))
	header.position = Vector2(28, 18)
	add_child(header)

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
