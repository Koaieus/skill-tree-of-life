class_name EdgeHighlightOverlay
extends Node2D

## World-space overlay that paints edge highlights for the [b]active highlight
## provider[/b] (see [HighlightController]) — the [RangeVisual] (rings + edges)
## a provider hands back from [method HighlightProvider.get_range_visual].
## Magic plans populate it from a [RangeFinder]; core-move populates it with its
## reachable / on-route edges. One overlay, many providers.
##
## Per-edge colour comes from [member RangeVisual.EdgeEntry.role]: NONE keeps
## the finder scene's stock golden look (attack ranges unchanged); other roles
## map through [member ROLE_COLORS]. Mounted as a child of [Graph] below
## [NodeHighlightOverlay] so node status rings keep painting on top.

const _DEFAULT_EDGE_SCENE: PackedScene = preload("res://attack/range_finder/visuals/range_edge.tscn")
const _DEFAULT_RING_SCENE: PackedScene = preload("res://attack/range_finder/visuals/range_ring.tscn")

## Role → edge colour. Absent role (incl. NONE) → leave the edge scene's own
## default colour untouched (the finder's golden range tint).
const ROLE_COLORS: Dictionary[int, Color] = {
	HighlightProvider.HighlightRole.PATH:        Color(0.3, 0.9, 0.85, 0.65),
	HighlightProvider.HighlightRole.REACHABLE:   Color(0.3, 0.9, 0.85, 0.65),
	HighlightProvider.HighlightRole.PROPAGATION: Color(1.0, 0.25, 0.2, 0.8),
}

@export var highlight_controller: HighlightController
@export var graph: Graph

## Drives the scaling behaviour of every instantiated [RangeEdgeVisual] —
## edge scenes pick this up via [member RangeEdgeVisual.scaling_mode].
@export var edge_scaling_mode: RangeEdgeVisual.ScalingMode = RangeEdgeVisual.ScalingMode.DIM_BY_REMAINING


func _ready() -> void:
	if highlight_controller == null:
		push_warning("EdgeHighlightOverlay missing highlight_controller; nothing to paint")
		return
	highlight_controller.provider_changed.connect(_on_repaint_needed.unbind(1))
	highlight_controller.provider_state_changed.connect(_on_repaint_needed)


func _on_repaint_needed() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if highlight_controller == null:
		return
	var provider := highlight_controller.provider
	if provider == null:
		return
	var visual := provider.get_range_visual()
	if visual == null or visual.is_empty():
		return
	var ring_scene: PackedScene = _provider_scene(provider, true)
	var edge_scene: PackedScene = _provider_scene(provider, false)
	for ring_data in visual.rings:
		if ring_scene == null:
			continue
		var ring: RangeRing = ring_scene.instantiate() as RangeRing
		if ring == null:
			continue
		add_child(ring)
		ring.configure(ring_data.position - global_position, ring_data.radius)
	for edge_data in visual.edges:
		if edge_scene == null:
			continue
		var ev: RangeEdgeVisual = edge_scene.instantiate() as RangeEdgeVisual
		if ev == null:
			continue
		ev.scaling_mode = edge_scaling_mode
		add_child(ev)
		ev.configure(edge_data.edge, edge_data.hops_remaining, edge_data.max_hops)
		if ROLE_COLORS.has(edge_data.role):
			ev.color = ROLE_COLORS[edge_data.role]


## Scene to instantiate for this provider's rings / edges. Magic plans carry
## bespoke finder scenes; everything else (core-move) uses the stock defaults.
func _provider_scene(provider: HighlightProvider, want_ring: bool) -> PackedScene:
	if provider is MagicAttackPlan:
		var mp := provider as MagicAttackPlan
		if mp.spell != null and mp.spell.targeting != null \
				and mp.spell.targeting.range_finder != null:
			var f: RangeFinder = mp.spell.targeting.range_finder
			return f.ring_scene if want_ring else f.edge_scene
	return _DEFAULT_RING_SCENE if want_ring else _DEFAULT_EDGE_SCENE
