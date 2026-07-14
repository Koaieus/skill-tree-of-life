@tool
extends Control
## Small live-generated graph for the procgen playground's "Node Graph" sub-tab
## (#166). Runs [GraphProcgen] at a preview node count — with `archetypes`
## stripped so it places positions/edges only, no content — on a private,
## invisible [Graph] instance, then draws the result.
##
## Node fill + the translucent background layer are both the same continuous
## [BudgetPolicy.budget_field] value (blue → red, matching [FieldMapView]'s
## gradient) — the composable-field overlay from #166's refined spec, now that
## nodes carry no baked-in roll to color by instead.
##
## A node isn't a generation result to inspect here — it's a *location* to
## sample, exactly like a click on the Map Sample tab. `node_clicked` hands the
## panel the node's position; the panel runs the same [method
## ProcgenPlaygroundPanel._sample_once] roll either surface uses, so "click a
## node" and "click the map at that spot" agree by construction.
##
## Hover uses Godot's native tooltip ([method _get_tooltip]) rather than a
## hand-rolled popup — cheap, positioned by the engine, no z-order bookkeeping.
##
## Stamp simulation (paint a stamp, see which nodes/how much budget it would
## touch) is planned for once #163 (archetype territory stamping) lands a
## stamp primitive to simulate — see #166.

signal node_clicked(node: SkillNode)

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _HOVER_RADIUS := 14.0
const _FIELD_CELL_RES := 40

var _graph: Graph
var _nodes: Array[SkillNode] = []
var _bounds := Rect2()
var _shape_mask: ShapeMask
var _budget_policy: BudgetPolicy
var _generating := false

var _fit := 1.0
var _draw_origin := Vector2.ZERO
var _field_min := 0.0
var _field_max := 0.0

# Screen-space cache rebuilt each _draw; used by hover/click hit-testing.
var _node_screen: Dictionary = {}   # SkillNode -> Vector2
var _node_screen_radius: Dictionary = {}   # SkillNode -> float


func _init() -> void:
	custom_minimum_size = Vector2(0, 340)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.visible = false
	add_child(_graph)


## Regenerates the preview graph from `cfg` (already sized down by the caller)
## on a fresh [Graph] instance — simpler and safer than diffing/removing the
## previous node set, and matches the instantiate-per-run pattern the procgen
## tests + sandbox already use.
##
## `archetypes` is cleared on a private copy before running — this view wants
## positions + edges only ("just nodes, at a location"); content belongs to
## the click-to-sample flow, not to generation. Stripping it here (rather than
## trusting every caller to do it) also skips the cluster-assign + budget +
## modifier-roll stages entirely, so the preview stays cheap regardless of
## `node_count`.
##
## Guarded against overlapping calls: a second `generate()` firing while the
## first is still awaiting `GraphProcgen.generate` would free the `_graph` the
## first call is actively populating (queue_free is deferred, so the in-flight
## `add_skill_node` calls would land on a graph mid-teardown). Callers should
## avoid firing a regenerate while one is in flight anyway; this is the backstop.
func generate(cfg: GraphProcgenConfig) -> void:
	if _generating:
		return
	_generating = true
	if _graph != null:
		_graph.queue_free()
	_graph = _GRAPH_SCENE.instantiate()
	_graph.visible = false
	add_child(_graph)
	await get_tree().process_frame

	var positions_cfg: GraphProcgenConfig = cfg.duplicate(true)
	positions_cfg.archetypes = []
	_budget_policy = positions_cfg.budget_policy
	_shape_mask = positions_cfg.shape_mask
	var result: Dictionary = await GraphProcgen.generate(positions_cfg, _graph)
	_nodes = result.get("nodes", [])
	_bounds = positions_cfg.shape_mask.aabb() if positions_cfg.shape_mask != null else Rect2()
	_compute_field_range()
	_generating = false
	queue_redraw()


func has_nodes() -> bool:
	return not _nodes.is_empty()


func _compute_field_range() -> void:
	_field_min = INF
	_field_max = -INF
	var field: ScalarField = null if _budget_policy == null else _budget_policy.budget_field
	for sn in _nodes:
		var v := 1.0 if field == null else field.sample(sn.position)
		_field_min = minf(_field_min, v)
		_field_max = maxf(_field_max, v)
	if _field_min > _field_max:
		_field_min = 1.0
		_field_max = 1.0
	elif is_equal_approx(_field_min, _field_max):
		_field_max = _field_min + 1e-3


func _node_field_value(sn: SkillNode) -> float:
	var field: ScalarField = null if _budget_policy == null else _budget_policy.budget_field
	return 1.0 if field == null else field.sample(sn.position)


# ── Interaction ───────────────────────────────────────────────────────────


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sn := _nearest_node((event as InputEventMouseButton).position)
		if sn != null:
			node_clicked.emit(sn)


func _get_tooltip(at_position: Vector2) -> String:
	var sn := _nearest_node(at_position)
	if sn == null:
		return ""
	var lines: Array[String] = []
	lines.append("field ×%.2f" % _node_field_value(sn))
	if _budget_policy != null:
		lines.append("base range %d–%d" % [_budget_policy.base_min, _budget_policy.base_max])
	lines.append("click to sample")
	return "\n".join(lines)


func _nearest_node(screen_pos: Vector2) -> SkillNode:
	var best: SkillNode = null
	var best_dist := INF
	for sn in _node_screen:
		if not is_instance_valid(sn):
			continue
		var p: Vector2 = _node_screen[sn]
		var d := p.distance_to(screen_pos)
		var r: float = _node_screen_radius.get(sn, _HOVER_RADIUS)
		if d <= maxf(r, _HOVER_RADIUS) and d < best_dist:
			best = sn
			best_dist = d
	return best


# ── Draw ──────────────────────────────────────────────────────────────────


func _draw() -> void:
	var ctrl_size := size
	draw_rect(Rect2(Vector2.ZERO, ctrl_size), Color(0.08, 0.08, 0.1))
	_node_screen.clear()
	_node_screen_radius.clear()

	if _nodes.is_empty() or _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		_label(Vector2(8, 16), "no graph yet — Regenerate")
		return

	var margin := 12.0
	_fit = minf(
			(ctrl_size.x - margin * 2.0) / _bounds.size.x,
			(ctrl_size.y - margin * 2.0) / _bounds.size.y)
	var draw_size := _bounds.size * _fit
	_draw_origin = (ctrl_size - draw_size) * 0.5

	_draw_field_overlay(draw_size)

	# Edges first so node dots sit on top.
	var edges := _graph.get_edges()
	for e in edges:
		if e.from == null or e.to == null or e.from == e.to:
			continue
		draw_line(_to_screen(e.from.position), _to_screen(e.to.position), Color(1, 1, 1, 0.15), 1.0)

	for sn in _nodes:
		var p := _to_screen(sn.position)
		var r := clampf(sn.radius * _fit, 4.0, 14.0)
		var t := 0.0 if is_equal_approx(_field_max, _field_min) else \
				(_node_field_value(sn) - _field_min) / (_field_max - _field_min)
		draw_circle(p, r, _heat(t))
		draw_arc(p, r, 0.0, TAU, 16, Color(1, 1, 1, 0.6), 1.5)
		_node_screen[sn] = p
		_node_screen_radius[sn] = r

	draw_rect(Rect2(_draw_origin, draw_size), Color(1, 1, 1, 0.18), false, 1.0)
	var field_note := "" if _budget_policy == null or _budget_policy.budget_field == null else \
			"   ·   field ×%.2f–%.2f" % [_field_min, _field_max]
	_label(Vector2(8, 14), "%d nodes%s   ·   hover for details, click to sample" %
			[_nodes.size(), field_note])


func _to_screen(world_pos: Vector2) -> Vector2:
	return _draw_origin + (world_pos - _bounds.position) * _fit


## Background heatmap of the raw [ScalarField] value (not the rolled per-node
## budget) under the graph — same cell-grid technique as [FieldMapView], drawn
## at reduced alpha so edges/node dots stay legible on top. No-op when the
## policy has no field assigned (nothing composed yet).
func _draw_field_overlay(draw_size: Vector2) -> void:
	var field: ScalarField = null if _budget_policy == null else _budget_policy.budget_field
	if field == null:
		return
	var values := PackedFloat32Array()
	values.resize(_FIELD_CELL_RES * _FIELD_CELL_RES)
	var vmin := INF
	var vmax := -INF
	var any_inside := false
	for y in _FIELD_CELL_RES:
		for x in _FIELD_CELL_RES:
			var wp := _bounds.position + Vector2(
					(x + 0.5) / _FIELD_CELL_RES * _bounds.size.x,
					(y + 0.5) / _FIELD_CELL_RES * _bounds.size.y)
			if _shape_mask != null and not _shape_mask.contains(wp):
				values[y * _FIELD_CELL_RES + x] = NAN
				continue
			var v := field.sample(wp)
			values[y * _FIELD_CELL_RES + x] = v
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
			any_inside = true
	if not any_inside:
		return
	if is_equal_approx(vmin, vmax):
		vmax = vmin + 1e-3

	var cell_w := draw_size.x / float(_FIELD_CELL_RES)
	var cell_h := draw_size.y / float(_FIELD_CELL_RES)
	for y in _FIELD_CELL_RES:
		for x in _FIELD_CELL_RES:
			var v: float = values[y * _FIELD_CELL_RES + x]
			if is_nan(v):
				continue
			var t := (v - vmin) / (vmax - vmin)
			var top_left := _draw_origin + Vector2(x * cell_w, y * cell_h)
			var c := _heat(t)
			c.a = 0.45
			draw_rect(Rect2(top_left, Vector2(cell_w + 1.0, cell_h + 1.0)), c)


## Blue → teal → yellow → red. Kept identical to [FieldMapView]'s gradient
## (private copy, same rationale — the two surfaces are allowed to diverge)
## so heat reads consistently between the map and graph sub-tabs.
func _heat(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		var u := t * 2.0
		return Color(0.1 + 0.1 * u, 0.25 + 0.55 * u, 0.85 - 0.25 * u)
	var u := (t - 0.5) * 2.0
	return Color(0.25 + 0.7 * u, 0.85 - 0.45 * u, 0.55 - 0.5 * u)


func _label(pos: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.82))
