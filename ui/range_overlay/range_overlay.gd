class_name RangeOverlay
extends Node2D

## World-space overlay that paints the active [AttackPlan]'s source-node
## reach — a [RangeVisual] handed back by the plan, populated by the active
## [RangeFinder]. Rings get instantiated from the finder's [code]ring_scene[/code],
## edges from [code]edge_scene[/code]; this overlay only owns the wiring, not
## the visual style.
##
## Mounted as a child of [Graph] below [AttackHighlightOverlay] so node
## status rings keep painting on top of edge highlights.

@export var battle_system: BattleSystem
@export var graph: Graph

## Drives the scaling behaviour of every instantiated [RangeEdgeVisual] —
## edge scenes pick this up via [member RangeEdgeVisual.scaling_mode].
@export var edge_scaling_mode: RangeEdgeVisual.ScalingMode = RangeEdgeVisual.ScalingMode.DIM_BY_REMAINING


func _ready() -> void:
	if battle_system == null:
		push_warning("RangeOverlay missing battle_system; nothing to paint")
		return
	battle_system.attack_plan_changed.connect(_on_repaint_needed.unbind(1))
	battle_system.attack_plan_state_changed.connect(_on_repaint_needed)


func _on_repaint_needed() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if battle_system == null:
		return
	var plan := battle_system.attack_plan
	if plan == null:
		return
	var visual := plan.get_source_range_visual()
	if visual == null or visual.is_empty():
		return
	var finder_ring_scene: PackedScene = _finder_scene(plan, true)
	var finder_edge_scene: PackedScene = _finder_scene(plan, false)
	for ring_data in visual.rings:
		if finder_ring_scene == null:
			continue
		var ring: RangeRing = finder_ring_scene.instantiate() as RangeRing
		if ring == null:
			continue
		add_child(ring)
		ring.configure(ring_data.position - global_position, ring_data.radius)
	for edge_data in visual.edges:
		if finder_edge_scene == null:
			continue
		var ev: RangeEdgeVisual = finder_edge_scene.instantiate() as RangeEdgeVisual
		if ev == null:
			continue
		ev.scaling_mode = edge_scaling_mode
		add_child(ev)
		ev.configure(edge_data.edge, edge_data.hops_remaining, edge_data.max_hops)


func _finder_scene(plan: AttackPlan, want_ring: bool) -> PackedScene:
	# Only MagicAttackPlan exposes a RangeFinder today; widen this later if
	# ranged / melee plans grow their own RangeFinder-driven visuals.
	if plan is MagicAttackPlan:
		var mp := plan as MagicAttackPlan
		if mp.spell != null and mp.spell.targeting != null \
				and mp.spell.targeting.range_finder != null:
			var f: RangeFinder = mp.spell.targeting.range_finder
			return f.ring_scene if want_ring else f.edge_scene
	return null
