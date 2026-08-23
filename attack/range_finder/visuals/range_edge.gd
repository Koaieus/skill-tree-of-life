@tool
class_name RangeEdgeVisual
extends Node2D

## Visual for one edge inside a hop-based reach. Reads endpoint positions
## from the live [Edge] each frame so the highlight rides moving nodes; the
## scaling mode controls how reach drain reads visually.
##
## Place this on its own layer / Node2D parent BELOW the node-ring overlay so
## edge highlights never paint over a SkillNode's status ring.

enum ScalingMode {
	FLAT,                 ## All lit edges look identical regardless of remaining hops.
	DIM_BY_REMAINING,     ## Alpha fades as hops_remaining → 0.
	THIN_BY_REMAINING,    ## Width thins as hops_remaining → 0.
	BOTH,                 ## Alpha + width both scale.
}

@export var edge: Edge = null:
	set(value):
		if edge == value:
			return
		_disconnect_edge()
		edge = value
		_connect_edge()
		queue_redraw()

@export var hops_remaining: int = 0:
	set(value):
		hops_remaining = value
		queue_redraw()

@export var max_hops: int = 1:
	set(value):
		max_hops = max(1, value)
		queue_redraw()

@export var color: Color = Color(1.0, 0.85, 0.0, 0.85):
	set(value):
		color = value
		queue_redraw()

@export var line_width: float = 4.0:
	set(value):
		line_width = value
		queue_redraw()

## Extra outward padding past each endpoint's perimeter so the highlight sits
## clearly outside the node's visible body instead of flush against it.
@export var endpoint_padding: float = 2.0:
	set(value):
		endpoint_padding = value
		queue_redraw()

@export var scaling_mode: ScalingMode = ScalingMode.FLAT:
	set(value):
		scaling_mode = value
		queue_redraw()

## Floor on the scaled alpha / width — keeps the deepest-hop highlight visible.
@export_range(0.0, 1.0, 0.05) var min_scale: float = 0.25:
	set(value):
		min_scale = clampf(value, 0.0, 1.0)
		queue_redraw()


func configure(p_edge: Edge, p_hops_remaining: int, p_max_hops: int) -> void:
	edge = p_edge
	max_hops = p_max_hops
	hops_remaining = p_hops_remaining


func _exit_tree() -> void:
	_disconnect_edge()


func _connect_edge() -> void:
	if edge == null:
		return
	if not edge.is_connected(&"endpoints_changed", _on_edge_changed):
		edge.endpoints_changed.connect(_on_edge_changed)


func _disconnect_edge() -> void:
	if edge == null:
		return
	if edge.is_connected(&"endpoints_changed", _on_edge_changed):
		edge.endpoints_changed.disconnect(_on_edge_changed)


func _on_edge_changed() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	# Nodes can move between frames; cheap redraw keeps the highlight glued.
	queue_redraw()


func _draw() -> void:
	if edge == null or edge.from == null or edge.to == null:
		return
	var s := _scale_factor()
	var alpha_scale := 1.0
	var width_scale := 1.0
	match scaling_mode:
		ScalingMode.FLAT:
			pass
		ScalingMode.DIM_BY_REMAINING:
			alpha_scale = s
		ScalingMode.THIN_BY_REMAINING:
			width_scale = s
		ScalingMode.BOTH:
			alpha_scale = s
			width_scale = s
	var tint := Color(color.r, color.g, color.b, color.a * alpha_scale)
	var w := line_width * width_scale
	var seg := SkillNode.segment_between(edge.from, edge.to, endpoint_padding)
	if seg.is_empty():
		return
	# `to_local`, not a global-point difference: `_draw` paints in local units,
	# and the two agree only while every ancestor sits at scale 1 (see
	# [NodeHighlightOverlay._draw]). A sandbox tab scales its Graph to fit.
	draw_line(to_local(seg[0]), to_local(seg[1]), tint, w, true)


func _scale_factor() -> float:
	# hops_remaining 0..max_hops → min_scale..1.0 (last hop still visible).
	var t := clampf(float(hops_remaining + 1) / float(max_hops), 0.0, 1.0)
	return lerpf(min_scale, 1.0, t)
