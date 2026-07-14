@tool
extends Control
## Small live-generated graph for the procgen playground's "Node Graph" sub-tab
## (#166). Runs [GraphProcgen] at a preview node count on a private, invisible
## [Graph] instance, then draws the result colour-coded by each node's rolled
## budget (blue → red heatmap, matching [FieldMapView]'s gradient) with a thin
## archetype-colour ring per node.
##
## Hover uses Godot's native tooltip ([method _get_tooltip]) rather than a
## hand-rolled popup — cheap, positioned by the engine, no z-order bookkeeping.
## Click emits `node_clicked` so the panel can roll sample cards at that node's
## already-rolled budget.

signal node_clicked(node: SkillNode)

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _HOVER_RADIUS := 14.0

var _graph: Graph
var _nodes: Array[SkillNode] = []
var _bounds := Rect2()
var _budget_policy: BudgetPolicy
var _generating := false

var _fit := 1.0
var _draw_origin := Vector2.ZERO
var _budget_min := 0.0
var _budget_max := 0.0

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

	_budget_policy = cfg.budget_policy
	var result: Dictionary = await GraphProcgen.generate(cfg, _graph)
	_nodes = result.get("nodes", [])
	_bounds = cfg.shape_mask.aabb() if cfg.shape_mask != null else Rect2()
	_compute_budget_range()
	_generating = false
	queue_redraw()


func has_nodes() -> bool:
	return not _nodes.is_empty()


func _compute_budget_range() -> void:
	_budget_min = INF
	_budget_max = -INF
	for sn in _nodes:
		var b := _node_budget(sn)
		_budget_min = minf(_budget_min, b)
		_budget_max = maxf(_budget_max, b)
	if _budget_min > _budget_max:
		_budget_min = 0.0
		_budget_max = 0.0
	elif is_equal_approx(_budget_min, _budget_max):
		_budget_max = _budget_min + 1.0


func _node_budget(sn: SkillNode) -> float:
	var fp: Dictionary = sn.get_meta("procgen_footprint", {})
	return float(fp.get("budget", 0))


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
	var fp: Dictionary = sn.get_meta("procgen_footprint", {})
	var archetype := String(sn.get_meta("base_type", &""))
	var primary_stat := String(sn.get_meta("primary_stat", &""))
	var budget := int(fp.get("budget", 0))
	var lines: Array[String] = []
	lines.append("archetype: %s" % (archetype if archetype != "" else "(none)"))
	if primary_stat != "":
		lines.append("primary stat: %s" % primary_stat)
	lines.append("budget: %d   (this graph: %d–%d)" % [budget, int(_budget_min), int(_budget_max)])
	if _budget_policy != null:
		lines.append("policy base range: %d–%d" % [_budget_policy.base_min, _budget_policy.base_max])
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

	# Edges first so node dots sit on top.
	var edges := _graph.get_edges()
	for e in edges:
		if e.from == null or e.to == null or e.from == e.to:
			continue
		draw_line(_to_screen(e.from.position), _to_screen(e.to.position), Color(1, 1, 1, 0.15), 1.0)

	for sn in _nodes:
		var p := _to_screen(sn.position)
		var r := clampf(sn.radius * _fit, 4.0, 14.0)
		var t := 0.0 if is_equal_approx(_budget_max, _budget_min) else \
				(_node_budget(sn) - _budget_min) / (_budget_max - _budget_min)
		draw_circle(p, r, _heat(t))
		draw_arc(p, r, 0.0, TAU, 16, sn.base_type_color, 1.5)
		_node_screen[sn] = p
		_node_screen_radius[sn] = r

	draw_rect(Rect2(_draw_origin, draw_size), Color(1, 1, 1, 0.18), false, 1.0)
	_label(Vector2(8, 14), "budget %d–%d over %d nodes   ·   hover for details, click to sample" %
			[int(_budget_min), int(_budget_max), _nodes.size()])


func _to_screen(world_pos: Vector2) -> Vector2:
	return _draw_origin + (world_pos - _bounds.position) * _fit


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
