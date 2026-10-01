@tool
class_name NodeHighlightOverlay
extends Node2D

## World-space overlay that paints a ring around every SkillNode tagged with a
## non-NONE [enum HighlightProvider.HighlightRole] by the [b]active highlight
## provider[/b] (see [HighlightController]). One overlay serves every provider —
## attack plans, core-move, future hover — since they all speak the same role
## vocabulary via [method HighlightProvider.get_node_role].
##
## Wired declaratively in `game_root.tscn`; a live sandbox tab gets the same
## overlay from `scenes/dev/sandbox_world.gd`'s `highlight` opt, which is why
## this is `@tool`.

@export var highlight_controller: HighlightController
@export var graph: Graph

# Plain role ring band (ring convention — see SkillNode.ring_centerline):
# `ring_inner_offset` is the gap from the node boundary to the ring's INNER edge.
# Drawn for every role with no indicator scene in `themes[key]` or `default_theme`.
@export var ring_inner_offset: float = 4.5
@export var ring_width: float = 3.0
@export var ring_segments: int = 32

## Provider theme key ([method HighlightProvider.get_theme_key]) -> its
## [IndicatorTheme]. A node's scene is [code]themes[key][/code]'s for its role,
## else [member default_theme]'s, else none (the plain ring).
@export var themes: Dictionary[StringName, IndicatorTheme] = {}

## Role -> [Indicator] scene for every key [member themes] leaves unmapped. A
## role with a scene mounts an instance as this overlay's child (and skips the
## plain ring); every other role keeps the ring.
## Shared resources — swap them, never mutate them in place.
@export var default_theme: IndicatorTheme = preload("res://ui/indicator/themes/default.tres")

# The range ring is a GAMEPLAY reach (world-space radius), not a decoration band,
# so it draws AT `range_radius` (centerline) and is deliberately exempt from the
# ring_inner_offset convention.
@export var range_ring_width: float = 1.5
@export var range_ring_segments: int = 64
## Dash periods around a range circle drawn below full fill (ranged: shots
## left / max shots) — see [method RangeRing.draw_reach].
@export_range(1, 64, 1) var range_ring_dash_periods: int = 12:
	set(value):
		range_ring_dash_periods = value
		queue_redraw()
@export var range_ring_alpha_idle: float = 0.10
@export var range_ring_alpha_active: float = 0.30

const ROLE_COLORS: Dictionary[HighlightProvider.HighlightRole, Color] = {
	HighlightProvider.HighlightRole.ORIGIN:          Color(1.0, 0.85, 0.0, 0.9),
	HighlightProvider.HighlightRole.MEMBER:          Color(1.0, 0.55, 0.1, 0.85),
	HighlightProvider.HighlightRole.IN_RANGE:        Color(0.45, 0.95, 0.45, 0.55),
	# Cyan, and deliberately in IN_RANGE's alpha band: both are CANDIDATE states
	# ("could cast from here" / "could hit this"), against the committed picks'
	# 0.9+ ORIGIN gold and HOSTILE_TARGET red. It reads next to green rather
	# than against them because casters and targets are shown at the same time
	# and must stay separable at a glance. REACHABLE/PATH are a similar teal but
	# belong to the core-move provider, and only one provider paints at a time.
	HighlightProvider.HighlightRole.CASTER:          Color(0.2, 0.95, 1.0, 0.6),
	HighlightProvider.HighlightRole.HOSTILE_TARGET:  Color(1.0, 0.2, 0.2, 0.95),
	HighlightProvider.HighlightRole.FRIENDLY_TARGET: Color(0.2, 0.7, 1.0, 0.95),
	HighlightProvider.HighlightRole.INVALID:         Color(0.45, 0.45, 0.45, 0.55),
	HighlightProvider.HighlightRole.REACHABLE:       Color(0.3, 0.9, 0.85, 0.7),
	HighlightProvider.HighlightRole.PATH:            Color(0.3, 0.9, 0.85, 0.55),
	HighlightProvider.HighlightRole.PROPAGATION:     Color(1.0, 0.25, 0.2, 0.85),
	HighlightProvider.HighlightRole.ALLOCATABLE:    Color(1.0, 0.75, 0.3, 0.65),
	HighlightProvider.HighlightRole.PENDING_REMAINDER: Color(1.0, 0.75, 0.3, 0.25),
	# #782: a defender the previewed swing will lose a vertex (or an edge) to.
	# Deliberately the hottest red on the board — it is the one role that says
	# "this costs YOU something", not "this is a thing you may do".
	HighlightProvider.HighlightRole.PREDICTED_THREAT: Color(1.0, 0.35, 0.15, 0.95),
	# Deliberately the same red as the aim-point HOSTILE_TARGET — no look
	# change in this unit (#1285); the roles split meaning, not pixels.
	HighlightProvider.HighlightRole.FORFEIT:          Color(1.0, 0.2, 0.2, 0.95),
}


func _ready() -> void:
	if highlight_controller == null:
		push_warning("NodeHighlightOverlay missing highlight_controller; nothing to paint")
		return
	highlight_controller.provider_changed.connect(_on_repaint_needed.unbind(1))
	highlight_controller.provider_state_changed.connect(_on_repaint_needed)


# Live indicator per node, diffed on every repaint signal so an unchanged
# target keeps its instance (and its spinner's phase). `_indicator_looks` holds
# the [theme key, role] each was mounted for; a change of either re-instances.
var _indicators: Dictionary[SkillNode, Indicator] = {}
var _indicator_looks: Dictionary[SkillNode, Array] = {}


func _on_repaint_needed() -> void:
	_sync_indicators()
	queue_redraw()


func _indicator_scene(key: StringName, role: int) -> PackedScene:
	if role == HighlightProvider.HighlightRole.NONE:
		return null
	var theme: IndicatorTheme = themes.get(key)
	var scene: PackedScene = theme.scene_for(role) if theme != null else null
	if scene == null and default_theme != null:
		scene = default_theme.scene_for(role)
	return scene


func _sync_indicators() -> void:
	var provider: HighlightProvider = null
	if highlight_controller != null and graph != null:
		provider = highlight_controller.provider
	var key: StringName = provider.get_theme_key() if provider != null else &""
	var wanted: Dictionary[SkillNode, PackedScene] = {}
	var roles: Dictionary[SkillNode, int] = {}
	if provider != null:
		for sn in graph.get_skill_nodes():
			var role: int = provider.get_node_role(sn)
			var scene := _indicator_scene(key, role)
			if scene != null:
				wanted[sn] = scene
				roles[sn] = role
	for sn in _indicators.keys():
		var live: Indicator = _indicators[sn]
		var keep := wanted.has(sn) and is_instance_valid(sn) and is_instance_valid(live) \
				and _indicator_looks[sn] == [key, roles[sn]] \
				and wanted[sn].resource_path == live.scene_file_path
		if not keep:
			if is_instance_valid(live):
				live.queue_free()
				remove_child(live)
			_indicators.erase(sn)
			_indicator_looks.erase(sn)
	for sn in wanted:
		var role: int = roles[sn]
		var ind: Indicator = _indicators.get(sn)
		if ind == null:
			ind = wanted[sn].instantiate() as Indicator
			ind.tint = ROLE_COLORS.get(role, Color.WHITE)
			add_child(ind)
			_indicators[sn] = ind
			_indicator_looks[sn] = [key, role]
		ind.position = to_local(sn.global_position)
		ind.radius = sn.radius
		ind.facing = provider.get_node_facing(sn)
		ind.order = provider.get_node_order(sn)
		ind.charge = provider.get_node_range_fill(sn)


func _draw() -> void:
	if highlight_controller == null or graph == null:
		return
	var provider := highlight_controller.provider
	if provider == null:
		return
	var key := provider.get_theme_key()
	for sn in graph.get_skill_nodes():
		var role: int = provider.get_node_role(sn)
		# `to_local`, not `global_position - global_position`: the difference of
		# two global points is a delta in SCREEN units, and `_draw` paints in the
		# overlay's own local units. Identical while the Graph sits at scale 1
		# (every level), wrong by the scale factor in a sandbox tab that fits the
		# board to a panel — the rings landed at a multiple of their node's offset.
		var center := to_local(sn.global_position)
		var range_radius := provider.get_node_range(sn)
		if range_radius > 0.0:
			var base: Color = ROLE_COLORS.get(HighlightProvider.HighlightRole.ORIGIN, Color.WHITE)
			var active := role == HighlightProvider.HighlightRole.ORIGIN
			var alpha := range_ring_alpha_active if active else range_ring_alpha_idle
			var tint := Color(base.r, base.g, base.b, alpha)
			RangeRing.draw_reach(self, center, range_radius, provider.get_node_range_fill(sn),
					range_ring_dash_periods, tint, range_ring_width, range_ring_segments)
		if role == HighlightProvider.HighlightRole.NONE or _indicator_scene(key, role) != null:
			continue
		var color: Color = ROLE_COLORS.get(role, Color.WHITE)
		var ring_c := SkillNode.ring_centerline(sn.radius, ring_inner_offset, ring_width)
		draw_arc(center, ring_c, 0.0, TAU, ring_segments, color, ring_width)
