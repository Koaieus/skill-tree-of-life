@tool
extends Control
## Small live-generated graph for the procgen playground's "Node Graph" sub-tab
## (#166). Runs [GraphProcgen] at a preview node count on a private, invisible
## [Graph] instance, then draws the result.
##
## Archetypes are kept for node coloring (BFS-grow cluster assignment) but
## [modifier_pool_set] and [guaranteed_placements] are stripped so content isn't
## rolled — the preview stays cheap. Node fill uses the continuous
## [BudgetPolicy.budget_field] value (blue → red heatmap, matching
## [FieldMapView]'s gradient); node border shows its assigned archetype colour.
##
## A node isn't a generation result to inspect here — it's a *location* to
## sample, exactly like a click on the Map Sample tab. `node_clicked` hands the
## panel the node's position; the panel runs the same
## [method ProcgenPlaygroundPanel._sample_once] roll either surface uses.
##
## Stamp simulation (#166): [method paint_stamp] creates an [ArchetypeStamp] at
## the clicked node's position, then re-assigns archetype colours for every node
## inside the stamp region (post-hoc, without re-running the pipeline).
## [method clear_stamps] restores the original BFS-grow assignments. Stamp
## regions are drawn as translucent circles on top of the graph.
##
## Hover uses Godot's native tooltip ([method _get_tooltip]) — shows field
## value, archetype name, base budget range, and budget prediction.

signal node_clicked(node: SkillNode)

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _HOVER_RADIUS := 14.0
const _FIELD_CELL_RES := 40

var _graph: Graph
var _nodes: Array[SkillNode] = []
var _bounds := Rect2()
var _shape_mask: ShapeMask
var _budget_policy: BudgetPolicy
var _archetypes: Array[ArchetypePolicy] = []
var _generating := false

## Per-node original BFS-grow archetype index (into _archetypes). Saved during
## generation; stamps override the live colour on _nodes but this is the
## restore target for [method clear_stamps].
var _original_arch_idx: Dictionary = {}   # SkillNode -> int (-1 = none)

var _fit := 1.0
var _draw_origin := Vector2.ZERO
var _field_min := 0.0
var _field_max := 0.0

var _node_screen: Dictionary = {}   # SkillNode -> Vector2
var _node_screen_radius: Dictionary = {}   # SkillNode -> float

## Active stamps painted during this session. Reset on [method clear_stamps]
## and on [method generate].
var _stamps: Array[ArchetypeStamp] = []

var _tooltip_rng := RandomNumberGenerator.new()


func _init() -> void:
	custom_minimum_size = Vector2(0, 340)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.visible = false
	add_child(_graph)


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
	# Keep archetypes so the BFS-grow assigns cluster colours — we only strip
	# content so no modifiers/addons are rolled per node.
	_budget_policy = positions_cfg.budget_policy
	_shape_mask = positions_cfg.shape_mask
	_archetypes = positions_cfg.archetypes.duplicate()
	positions_cfg.modifier_pool_set = null
	positions_cfg.guaranteed_placements = []
	# Full generate — archetypes are populated so nodes get base_type_color.
	var result: Dictionary = await GraphProcgen.generate(positions_cfg, _graph)
	_nodes = result.get("nodes", [])
	_stamps.clear()
	_original_arch_idx.clear()
	# Snapshot each node's original BFS-grow archetype index for restore.
	for i in _nodes.size():
		var sn: SkillNode = _nodes[i]
		if sn.has_meta("base_type"):
			var bt: StringName = sn.get_meta("base_type")
			for k in _archetypes.size():
				if _archetypes[k] != null and _archetypes[k].id == bt:
					_original_arch_idx[sn] = k
					break
		else:
			_original_arch_idx[sn] = -1
	_bounds = positions_cfg.shape_mask.aabb() if positions_cfg.shape_mask != null else Rect2()
	_compute_field_range()
	_generating = false
	queue_redraw()


func has_nodes() -> bool:
	return not _nodes.is_empty()


## Paint a stamp: create an [ArchetypeStamp] centred at the clicked node's
## position with the panel's chosen archetype + radius, then re-assign every
## node inside the stamp region to the new archetype. The stamp persists until
## [method clear_stamps] or the next [method generate].
func paint_stamp(center_world: Vector2, radius: float, archetype_idx: int) -> void:
	if archetype_idx < 0 or archetype_idx >= _archetypes.size():
		return
	var stamp := ArchetypeStamp.new()
	stamp.mode = ArchetypeStamp.RegionMode.EUCLIDEAN
	stamp.position = center_world
	stamp.radius = radius
	stamp.archetype_idx = archetype_idx
	_stamps.append(stamp)

	var policy: ArchetypePolicy = _archetypes[archetype_idx]
	for sn in _nodes:
		if sn.position.distance_squared_to(center_world) <= radius * radius:
			sn.base_type_color = policy.color
			sn.set_meta("base_type", policy.id)
	queue_redraw()


## Remove all active stamps and restore every node to its original BFS-grow
## archetype colour.
func clear_stamps() -> void:
	_stamps.clear()
	for sn in _nodes:
		var idx: int = _original_arch_idx.get(sn, -1)
		if idx >= 0 and idx < _archetypes.size():
			var policy: ArchetypePolicy = _archetypes[idx]
			sn.base_type_color = policy.color
			sn.set_meta("base_type", policy.id)
	queue_redraw()


func has_stamps() -> bool:
	return not _stamps.is_empty()


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
	var arch_name := String(sn.get_meta("base_type", &"?"))
	lines.append(arch_name)
	lines.append("field ×%.2f" % _node_field_value(sn))
	if _budget_policy != null:
		lines.append("base range %d–%d" % [_budget_policy.base_min, _budget_policy.base_max])
		var breakdown := _budget_policy.compute_budget_breakdown(arch_name, sn.position, [], _tooltip_rng)
		lines.append("budget ~%d" % breakdown.budget)
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
	_draw_stamp_regions()

	# Edges first so node dots sit on top.
	var edges := _graph.get_edges()
	for e in edges:
		if e.from == null or e.to == null or e.from == e.to:
			continue
		draw_line(_to_screen(e.from.position), _to_screen(e.to.position), Color(1, 1, 1, 0.15), 1.0)

	for sn in _nodes:
		var p := _to_screen(sn.position)
		var r := clampf(sn.radius * _fit, 4.0, 14.0)
		# Fill: budget-field heatmap.
		var t := 0.0 if is_equal_approx(_field_max, _field_min) else \
				(_node_field_value(sn) - _field_min) / (_field_max - _field_min)
		draw_circle(p, r, _heat(t))
		# Border: archetype colour.
		var arch_color := sn.base_type_color
		if arch_color.a < 0.01:
			arch_color = Color(0.4, 0.4, 0.4)
		draw_arc(p, r - 1.0, 0.0, TAU, 16, arch_color, 1.5)
		draw_arc(p, r, 0.0, TAU, 16, Color(1, 1, 1, 0.6), 1.5)
		_node_screen[sn] = p
		_node_screen_radius[sn] = r

	draw_rect(Rect2(_draw_origin, draw_size), Color(1, 1, 1, 0.18), false, 1.0)
	var field_note := "" if _budget_policy == null or _budget_policy.budget_field == null else \
			"   ·   field ×%.2f–%.2f" % [_field_min, _field_max]
	var stamp_note := "" if _stamps.is_empty() else "   ·   %d stamp%s" % [_stamps.size(), "s" if _stamps.size() != 1 else ""]
	_label(Vector2(8, 14), "%d nodes%s%s   ·   hover for details, click to sample" %
			[_nodes.size(), field_note, stamp_note])


func _to_screen(world_pos: Vector2) -> Vector2:
	return _draw_origin + (world_pos - _bounds.position) * _fit


## Draw translucent circles for each euclidean stamp region.
func _draw_stamp_regions() -> void:
	for stamp in _stamps:
		if stamp == null or stamp.mode != ArchetypeStamp.RegionMode.EUCLIDEAN:
			continue
		var screen_center := _to_screen(stamp.position)
		var screen_radius := stamp.radius * _fit
		if screen_radius <= 0.0:
			continue
		var arch_color := Color(1, 1, 1, 0.3)
		if stamp.archetype_idx >= 0 and stamp.archetype_idx < _archetypes.size():
			arch_color = _archetypes[stamp.archetype_idx].color
			arch_color.a = 0.25
		draw_circle(screen_center, screen_radius, arch_color)
		draw_arc(screen_center, screen_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.4), 1.0)


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
