class_name NodeHighlightOverlay
extends Node2D

## World-space overlay that paints a ring around every SkillNode tagged with a
## non-NONE [enum HighlightProvider.HighlightRole] by the [b]active highlight
## provider[/b] (see [HighlightController]). One overlay serves every provider —
## attack plans, core-move, future hover — since they all speak the same role
## vocabulary via [method HighlightProvider.get_node_role].
##
## Mounted programmatically by GameRoot so no scene wiring is required.

@export var highlight_controller: HighlightController
@export var graph: Graph

const RING_PADDING: float = 6.0
const RING_WIDTH: float = 3.0
const RING_SEGMENTS: int = 32

const RANGE_RING_WIDTH: float = 1.5
const RANGE_RING_SEGMENTS: int = 64
const RANGE_RING_ALPHA_IDLE: float = 0.10
const RANGE_RING_ALPHA_ACTIVE: float = 0.30

const ROLE_COLORS: Dictionary[int, Color] = {
	HighlightProvider.HighlightRole.ORIGIN:          Color(1.0, 0.85, 0.0, 0.9),
	HighlightProvider.HighlightRole.MEMBER:          Color(1.0, 0.55, 0.1, 0.85),
	HighlightProvider.HighlightRole.IN_RANGE:        Color(0.45, 0.95, 0.45, 0.55),
	HighlightProvider.HighlightRole.HOSTILE_TARGET:  Color(1.0, 0.2, 0.2, 0.95),
	HighlightProvider.HighlightRole.FRIENDLY_TARGET: Color(0.2, 0.7, 1.0, 0.95),
	HighlightProvider.HighlightRole.INVALID:         Color(0.45, 0.45, 0.45, 0.55),
	HighlightProvider.HighlightRole.REACHABLE:       Color(0.3, 0.9, 0.85, 0.7),
	HighlightProvider.HighlightRole.PATH:            Color(0.3, 0.9, 0.85, 0.55),
	HighlightProvider.HighlightRole.PROPAGATION:     Color(1.0, 0.25, 0.2, 0.85),
}


func _ready() -> void:
	if highlight_controller == null:
		push_warning("NodeHighlightOverlay missing highlight_controller; nothing to paint")
		return
	highlight_controller.provider_changed.connect(_on_repaint_needed.unbind(1))
	highlight_controller.provider_state_changed.connect(_on_repaint_needed)


func _on_repaint_needed() -> void:
	queue_redraw()


func _draw() -> void:
	if highlight_controller == null or graph == null:
		return
	var provider := highlight_controller.provider
	if provider == null:
		return
	for sn in graph.get_skill_nodes():
		var role: int = provider.get_node_role(sn)
		var center := sn.global_position - global_position
		var range_radius := provider.get_node_range(sn)
		if range_radius > 0.0:
			var base: Color = ROLE_COLORS.get(HighlightProvider.HighlightRole.ORIGIN, Color.WHITE)
			var active := role == HighlightProvider.HighlightRole.ORIGIN
			var alpha := RANGE_RING_ALPHA_ACTIVE if active else RANGE_RING_ALPHA_IDLE
			var tint := Color(base.r, base.g, base.b, alpha)
			draw_arc(center, range_radius, 0.0, TAU, RANGE_RING_SEGMENTS, tint, RANGE_RING_WIDTH)
		if role == HighlightProvider.HighlightRole.NONE:
			continue
		var color: Color = ROLE_COLORS.get(role, Color.WHITE)
		draw_arc(center, sn.radius + RING_PADDING, 0.0, TAU, RING_SEGMENTS, color, RING_WIDTH)
