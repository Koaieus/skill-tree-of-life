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

# Selection / status ring band (ring convention — see SkillNode.ring_centerline):
# `ring_inner_offset` is the gap from the node boundary to the ring's INNER edge.
# Default 4.5/3.0 → spans radius+4.5 .. radius+7.5, which currently overlaps the
# hover band (radius .. radius+8). That overlap, plus a possible hover-as-glow
# rethink, is tracked as a design follow-up (see #67 discussion) — not changed
# here so this refactor preserves the rendered pixels.
@export var ring_inner_offset: float = 4.5
@export var ring_width: float = 3.0
@export var ring_segments: int = 32

# The range ring is a GAMEPLAY reach (world-space radius), not a decoration band,
# so it draws AT `range_radius` (centerline) and is deliberately exempt from the
# ring_inner_offset convention.
@export var range_ring_width: float = 1.5
@export var range_ring_segments: int = 64
@export var range_ring_alpha_idle: float = 0.10
@export var range_ring_alpha_active: float = 0.30

const ROLE_COLORS: Dictionary[HighlightProvider.HighlightRole, Color] = {
	HighlightProvider.HighlightRole.ORIGIN:          Color(1.0, 0.85, 0.0, 0.9),
	HighlightProvider.HighlightRole.MEMBER:          Color(1.0, 0.55, 0.1, 0.85),
	HighlightProvider.HighlightRole.IN_RANGE:        Color(0.45, 0.95, 0.45, 0.55),
	HighlightProvider.HighlightRole.HOSTILE_TARGET:  Color(1.0, 0.2, 0.2, 0.95),
	HighlightProvider.HighlightRole.FRIENDLY_TARGET: Color(0.2, 0.7, 1.0, 0.95),
	HighlightProvider.HighlightRole.INVALID:         Color(0.45, 0.45, 0.45, 0.55),
	HighlightProvider.HighlightRole.REACHABLE:       Color(0.3, 0.9, 0.85, 0.7),
	HighlightProvider.HighlightRole.PATH:            Color(0.3, 0.9, 0.85, 0.55),
	HighlightProvider.HighlightRole.PROPAGATION:     Color(1.0, 0.25, 0.2, 0.85),
	HighlightProvider.HighlightRole.ALLOCATABLE:    Color(1.0, 0.75, 0.3, 0.65),
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
			var alpha := range_ring_alpha_active if active else range_ring_alpha_idle
			var tint := Color(base.r, base.g, base.b, alpha)
			draw_arc(center, range_radius, 0.0, TAU, range_ring_segments, tint, range_ring_width)
		if role == HighlightProvider.HighlightRole.NONE:
			continue
		var color: Color = ROLE_COLORS.get(role, Color.WHITE)
		var ring_c := SkillNode.ring_centerline(sn.radius, ring_inner_offset, ring_width)
		draw_arc(center, ring_c, 0.0, TAU, ring_segments, color, ring_width)
