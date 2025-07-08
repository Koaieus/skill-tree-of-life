extends Node
class_name GraphTransform

signal zoom_changed(new_zoom: float)

var zoom := Vector2.ONE
var scroll_offset := Vector2.ZERO
var _graph: GraphEdit

func to_viewport(logical_pos: Vector2) -> Vector2:
	# GraphEdit does: viewport_pos = logical_pos * zoom + scroll_offset
	return logical_pos * zoom + scroll_offset

func to_logical(viewport_pos: Vector2) -> Vector2:
	# invert the transform
	return (viewport_pos - scroll_offset) / zoom

func bind_graph(graph: GraphEdit) -> void:
	# initial bind
	zoom = Vector2.ONE * graph.zoom
	scroll_offset = graph.scroll_offset
	# connect offset signal
	graph.scroll_offset_changed.connect(_on_offset_changed)
	# store reference for polling
	_graph = graph

func _process(_delta):
	if not _graph:
		return
	var z = _graph.zoom
	if z != zoom.x:  # assume uniform scaling
		zoom = Vector2.ONE * z
		zoom_changed.emit(z)

func _on_zoom_changed(new_zoom: float):
	zoom = Vector2.ONE * new_zoom

func _on_offset_changed(new_offset: Vector2):
	scroll_offset = new_offset
