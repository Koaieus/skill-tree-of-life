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
			draw_arc(center, range_radius, 0.0, TAU, range_ring_segments, tint, range_ring_width)
		if role == HighlightProvider.HighlightRole.NONE:
			continue
		var color: Color = ROLE_COLORS.get(role, Color.WHITE)
		var ring_c := SkillNode.ring_centerline(sn.radius, ring_inner_offset, ring_width)
		draw_arc(center, ring_c, 0.0, TAU, ring_segments, color, ring_width)
