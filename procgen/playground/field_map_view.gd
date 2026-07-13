@tool
extends Control
## Interactive budget-field heatmap for a [GraphProcgenConfig], used by the
## procgen playground tab (#166). Draws the [ShapeMask] + the
## [BudgetPolicy.budget_field] as a blue→red heatmap and starter dots, then
## turns a click into a world position (`map_clicked`) so the panel can roll a
## batch of sample draws at that spot.
##
## Drawing is adapted from `addons/procgen_preview/preview_control.gd` (the
## inspector heatmap); kept as a private copy on purpose — the two surfaces
## diverge (this one is clickable + marks the sampled point).

signal map_clicked(world_pos: Vector2)

const _CELL_RES := 48
const _MARGIN := 12.0

var _config: GraphProcgenConfig

# World↔screen transform captured each _draw so a click can be inverted.
var _fit := 1.0
var _draw_origin := Vector2.ZERO
var _bounds := Rect2()
var _has_transform := false

# Last sampled world position, drawn as a crosshair marker.
var _marker_world := Vector2.ZERO
var _has_marker := false


func _init() -> void:
	custom_minimum_size = Vector2(0, 340)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_config(c: GraphProcgenConfig) -> void:
	_config = c
	_has_marker = false
	queue_redraw()


func set_marker(world_pos: Vector2) -> void:
	_marker_world = world_pos
	_has_marker = true
	queue_redraw()


func has_marker() -> bool:
	return _has_marker


func marker_world() -> Vector2:
	return _marker_world


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _has_transform or _fit <= 0.0:
			return
		var local: Vector2 = (event as InputEventMouseButton).position
		var world := _bounds.position + (local - _draw_origin) / _fit
		if _config != null and _config.shape_mask != null and not _config.shape_mask.contains(world):
			return  # clicks outside the shape don't sample
		_marker_world = world
		_has_marker = true
		queue_redraw()
		map_clicked.emit(world)


func _budget_field() -> ScalarField:
	if _config != null and _config.budget_policy != null:
		return _config.budget_policy.budget_field
	return null


func _draw() -> void:
	var ctrl_size := size
	draw_rect(Rect2(Vector2.ZERO, ctrl_size), Color(0.08, 0.08, 0.1))
	_has_transform = false
	if _config == null or _config.shape_mask == null or ctrl_size.x < 8.0 or ctrl_size.y < 8.0:
		_label(Vector2(8, 16), "no shape_mask assigned")
		return
	_bounds = _config.shape_mask.aabb()
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		_label(Vector2(8, 16), "shape_mask has empty AABB")
		return

	_fit = minf(
			(ctrl_size.x - _MARGIN * 2.0) / _bounds.size.x,
			(ctrl_size.y - _MARGIN * 2.0) / _bounds.size.y)
	var draw_size := _bounds.size * _fit
	_draw_origin = (ctrl_size - draw_size) * 0.5
	_has_transform = true

	var field := _budget_field()

	# Two-pass: sample to find value range, then draw normalised.
	var values := PackedFloat32Array()
	values.resize(_CELL_RES * _CELL_RES)
	var vmin := INF
	var vmax := -INF
	var any_inside := false
	for y in _CELL_RES:
		for x in _CELL_RES:
			var wp := _bounds.position + Vector2(
					(x + 0.5) / _CELL_RES * _bounds.size.x,
					(y + 0.5) / _CELL_RES * _bounds.size.y)
			if not _config.shape_mask.contains(wp):
				values[y * _CELL_RES + x] = NAN
				continue
			var v := 1.0 if field == null else field.sample(wp)
			values[y * _CELL_RES + x] = v
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
			any_inside = true
	if not any_inside:
		_label(Vector2(8, 16), "shape_mask contains no points in its AABB")
		return
	if is_equal_approx(vmin, vmax):
		vmax = vmin + 1e-3

	var cell_w := draw_size.x / float(_CELL_RES)
	var cell_h := draw_size.y / float(_CELL_RES)
	for y in _CELL_RES:
		for x in _CELL_RES:
			var v: float = values[y * _CELL_RES + x]
			if is_nan(v):
				continue
			var t := (v - vmin) / (vmax - vmin)
			var top_left := _draw_origin + Vector2(x * cell_w, y * cell_h)
			draw_rect(Rect2(top_left, Vector2(cell_w + 1.0, cell_h + 1.0)), _heat(t))

	draw_rect(Rect2(_draw_origin, draw_size), Color(1, 1, 1, 0.18), false, 1.0)

	# Starter markers.
	for sp in _config.starting_points:
		if sp == null:
			continue
		var p := _draw_origin + (sp.position - _bounds.position) * _fit
		draw_circle(p, 7.0, Color(0, 0, 0, 0.75))
		draw_circle(p, 5.0, Color(1, 1, 1, 0.95))

	# Sampled-point crosshair.
	if _has_marker:
		var m := _draw_origin + (_marker_world - _bounds.position) * _fit
		draw_circle(m, 9.0, Color(0, 0, 0, 0.7))
		draw_arc(m, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.95), 2.0)
		draw_line(m - Vector2(13, 0), m + Vector2(13, 0), Color(1, 1, 1, 0.9), 1.5)
		draw_line(m - Vector2(0, 13), m + Vector2(0, 13), Color(1, 1, 1, 0.9), 1.5)

	var field_label := "no budget_field" if field == null else "budget field  min %.2f  max %.2f" % [vmin, vmax]
	_label(Vector2(8, 14), field_label + "   ·   click to sample")


func _heat(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	# Blue → teal → yellow → red.
	if t < 0.5:
		var u := t * 2.0
		return Color(0.1 + 0.1 * u, 0.25 + 0.55 * u, 0.85 - 0.25 * u)
	var u := (t - 0.5) * 2.0
	return Color(0.25 + 0.7 * u, 0.85 - 0.45 * u, 0.55 - 0.5 * u)


func _label(pos: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.82))
