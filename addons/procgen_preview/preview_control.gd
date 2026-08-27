@tool
extends Control

## Renders the [ShapeMask] + [ScalarField] of a [GraphProcgenConfig] as a
## heatmap, plus dots for each [StartingPoint]. Lives in the inspector
## header via [EditorInspectorPlugin._parse_begin]. Subscribes to the
## config's `changed` signal AND to each sub-resource's `changed`, so
## tweaking shape radius / gradient values redraws live.
##
## Why double-subscribe: a Resource emits `changed` when its own @export
## props are edited, but not when a nested sub-resource changes. The config
## fires `changed` on slot reassignment (mask swap, field swap), at which
## point we rebind the deep listeners.

const _CELL_RES := 56

var _config: GraphProcgenConfig
var _bound_subs: Array[Resource] = []


func _init() -> void:
	custom_minimum_size = Vector2(0, 320)


func set_config(c: GraphProcgenConfig) -> void:
	_unbind_all()
	_config = c
	if _config != null:
		_config.changed.connect(_on_config_changed)
		_rebind_subs()
	queue_redraw()


func _exit_tree() -> void:
	_unbind_all()


func _on_config_changed() -> void:
	_rebind_subs()
	queue_redraw()


func _on_sub_changed() -> void:
	queue_redraw()


func _unbind_all() -> void:
	if _config != null and _config.changed.is_connected(_on_config_changed):
		_config.changed.disconnect(_on_config_changed)
	for r in _bound_subs:
		if r != null and r.changed.is_connected(_on_sub_changed):
			r.changed.disconnect(_on_sub_changed)
	_bound_subs.clear()


func _rebind_subs() -> void:
	for r in _bound_subs:
		if r != null and r.changed.is_connected(_on_sub_changed):
			r.changed.disconnect(_on_sub_changed)
	_bound_subs.clear()
	if _config == null:
		return
	var subs: Array[Resource] = []
	if _config.shape.shape_mask != null:
		subs.append(_config.shape.shape_mask)
	if _config.content.budget_policy != null:
		subs.append(_config.content.budget_policy)
		if _config.content.budget_policy.budget_field != null:
			subs.append(_config.content.budget_policy.budget_field)
	for sp in _config.starting.starting_points:
		if sp != null:
			subs.append(sp)
	for r in subs:
		r.changed.connect(_on_sub_changed)
		_bound_subs.append(r)


# ── Draw ──────────────────────────────────────────────────────────────────


func _draw() -> void:
	var ctrl_size := size
	draw_rect(Rect2(Vector2.ZERO, ctrl_size), Color(0.08, 0.08, 0.1))
	if _config == null or _config.shape.shape_mask == null or ctrl_size.x < 8.0 or ctrl_size.y < 8.0:
		_draw_label(Vector2(8, 16), "no shape_mask assigned")
		return
	var bounds: Rect2 = _config.shape.shape_mask.aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_draw_label(Vector2(8, 16), "shape_mask has empty AABB")
		return
	var budget_field: ScalarField = _config.content.budget_policy.budget_field if _config.content.budget_policy != null else null

	var margin := 12.0
	var fit := minf(
			(ctrl_size.x - margin * 2.0) / bounds.size.x,
			(ctrl_size.y - margin * 2.0) / bounds.size.y)
	var draw_size := bounds.size * fit
	var draw_origin := (ctrl_size - draw_size) * 0.5

	# Two-pass: first sample to find value range, then draw normalised.
	var values := PackedFloat32Array()
	values.resize(_CELL_RES * _CELL_RES)
	var vmin := INF
	var vmax := -INF
	var any_inside := false
	for y in _CELL_RES:
		for x in _CELL_RES:
			var wp := bounds.position + Vector2(
					(x + 0.5) / _CELL_RES * bounds.size.x,
					(y + 0.5) / _CELL_RES * bounds.size.y)
			if not _config.shape.shape_mask.contains(wp):
				values[y * _CELL_RES + x] = NAN
				continue
			var v := 1.0 if budget_field == null else budget_field.sample(wp)
			values[y * _CELL_RES + x] = v
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
			any_inside = true
	if not any_inside:
		_draw_label(Vector2(8, 16), "shape_mask contains no points in its AABB")
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
			var top_left := draw_origin + Vector2(x * cell_w, y * cell_h)
			draw_rect(Rect2(top_left, Vector2(cell_w + 1.0, cell_h + 1.0)), _heat(t))

	draw_rect(Rect2(draw_origin, draw_size), Color(1, 1, 1, 0.18), false, 1.0)

	# Starter markers.
	for sp in _config.starting.starting_points:
		if sp == null:
			continue
		var p := draw_origin + (sp.position - bounds.position) * fit
		draw_circle(p, 7.0, Color(0, 0, 0, 0.75))
		draw_circle(p, 5.0, Color(1, 1, 1, 0.95))
		if sp.id != &"":
			_draw_label(p + Vector2(9, -6), String(sp.id))

	_draw_label(Vector2(8, 14), "field min %.2f  max %.2f  (cells %d²)" % [vmin, vmax, _CELL_RES])


func _heat(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	# Blue → teal → yellow → red.
	if t < 0.5:
		var u := t * 2.0
		return Color(0.1 + 0.1 * u, 0.25 + 0.55 * u, 0.85 - 0.25 * u)
	var u := (t - 0.5) * 2.0
	return Color(0.25 + 0.7 * u, 0.85 - 0.45 * u, 0.55 - 0.5 * u)


func _draw_label(pos: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.78))
