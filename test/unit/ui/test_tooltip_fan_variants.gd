extends GutTest

## Tooltip V2 (#226) — structural checks on the three occupancy-class variant
## scenes: the reserved HP band (Decision 3), no-two-panels-overlap, and the
## z-sandwich (HoloPanel z=-1 / content z=0 / ScanlineOverlay z=+1). All
## geometric, none a screenshot — see #226's report for what stays
## editor-judgment (final placement/prettiness) vs. what's asserted here.

const _UNOWNED := preload("res://ui/tooltip_fan/variants/unowned.tscn")
const _OWNED := preload("res://ui/tooltip_fan/variants/owned.tscn")
const _OWNED_CORE := preload("res://ui/tooltip_fan/variants/owned_core.tscn")

## Decision 3: no panel may occupy y in [-70,-28], |x| <= 45 in node-local
## space (the reserved HP band above the node's HealthBar/CoreHealthBar).
const _BAND := Rect2(Vector2(-45.0, -70.0), Vector2(90.0, 42.0))


func _panel_rects(variant: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for n in variant.find_children("*", "FanPanel", true, false):
		var panel := n as FanPanel
		# Global-in-variant-space rect: FanPanel nodes may be nested a level
		# deep (inside a FanUnit), so fold the unit's own position in too —
		# every unit in these variants sits at (0,0) relative to its variant,
		# but this stays correct even if that ever changes.
		var unit_pos: Vector2 = panel.get_parent().position if panel.get_parent() is Node2D else Vector2.ZERO
		var rect := FanAnchor.panel_rect_of(panel)
		rect.position += unit_pos
		out.append(rect)
	return out


func _instantiate(scene: PackedScene) -> Node:
	var inst := scene.instantiate()
	add_child(inst)
	autofree(inst)
	return inst


func test_no_panel_occupies_the_reserved_hp_band_in_any_variant() -> void:
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		for rect in _panel_rects(inst):
			assert_false(rect.intersects(_BAND),
				"%s: panel rect %s must not intersect the reserved HP band %s" % [scene.resource_path, rect, _BAND])


func test_no_two_panels_overlap_in_any_variant() -> void:
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		var rects := _panel_rects(inst)
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				assert_false(rects[i].intersects(rects[j]),
					"%s: panel %d overlaps panel %d (%s vs %s)" % [scene.resource_path, i, j, rects[i], rects[j]])


func test_z_sandwich_is_set_up_on_every_content_panel() -> void:
	# Structural assertion ONLY — see the #226 report: nobody has visually
	# confirmed this renders as a hologram-with-scanlines-on-top. This proves
	# the z_index values are wired correctly, nothing about pixels.
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		for n in inst.find_children("*", "FanPanel", true, false):
			var panel := n as FanPanel
			var skin := panel.get_skin()
			if skin == null:
				continue
			assert_eq(skin.z_index, -1, "%s: skin (HoloPanel) must be z=-1" % panel.name)
			var overlay := panel.get_node_or_null("ScanlineOverlay")
			if overlay != null:
				assert_eq(overlay.z_index, 1, "%s: ScanlineOverlay must be z=+1" % panel.name)
			var content := panel.get_node_or_null("Content")
			if content != null:
				assert_eq(content.z_index, 0, "%s: content must be z=0" % panel.name)


func test_owned_variant_adds_the_owner_panel_over_unowned() -> void:
	var unowned := _instantiate(_UNOWNED)
	var owned := _instantiate(_OWNED)
	var unowned_panels := unowned.find_children("*", "FanPanel", true, false)
	var owned_panels := owned.find_children("*", "FanPanel", true, false)
	assert_eq(owned_panels.size(), unowned_panels.size() + 1, "owned.tscn adds exactly the Owner panel")


func test_owned_core_variant_adds_the_core_panel_over_owned() -> void:
	var owned := _instantiate(_OWNED)
	var owned_core := _instantiate(_OWNED_CORE)
	var owned_panels := owned.find_children("*", "FanPanel", true, false)
	var owned_core_panels := owned_core.find_children("*", "FanPanel", true, false)
	assert_eq(owned_core_panels.size(), owned_panels.size() + 1, "owned_core.tscn adds exactly the Core panel")


func _edge_name(anchor: Vector2, rect: Rect2) -> String:
	if is_equal_approx(anchor.x, rect.position.x):
		return "left"
	if is_equal_approx(anchor.x, rect.position.x + rect.size.x):
		return "right"
	if is_equal_approx(anchor.y, rect.position.y):
		return "top"
	return "bottom"


func _actual_edge_of_route(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float) -> String:
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {
		"trunk": trunk_frac, "trunk_dir": trunk_dir,
	})
	var leg := pts[pts.size() - 1] - pts[pts.size() - 2]
	if absf(leg.x) >= absf(leg.y):
		return "left" if leg.x >= 0.0 else "right"
	return "top" if leg.y >= 0.0 else "bottom"


## Decision 4 must hold for every shipped unit, not just synthetic
## quadrants: (1) the trace's CURRENT `to_point` must equal what
## [FanAnchor.derive_anchor] derives fresh from the panel's live position —
## i.e. nothing here is a stale/hand-authored value masquerading as derived —
## and (2) the route TraceRouter actually draws to that point must arrive on
## the SAME edge the point sits on (the exact bug review caught: a
## centre-only guess can name an edge the drawn route doesn't agree with).
## `no-overshoot` alone can't catch that bug — a leg can slide along a
## panel's edge without ever reading as "inside" it — so it isn't asserted
## here as a substitute for the edge check.
func test_every_fan_traces_terminus_is_self_consistent_in_every_variant() -> void:
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		await get_tree().process_frame
		for unit in inst.find_children("*", "FanUnit", true, false):
			var trace: FanTrace = unit.get_node_or_null("%Trace")
			var panel: FanPanel = unit.get_node_or_null("%Panel")
			if trace == null or panel == null:
				continue
			var rect := FanAnchor.panel_rect_of(panel)
			var slide: float = (unit as FanUnit).anchor_slide
			var expected := FanAnchor.derive_anchor(trace.from_point, rect, trace.trunk_dir, trace.bend_start, slide)
			assert_eq(trace.to_point, expected,
				"%s/%s: to_point must equal a fresh derive_anchor() of the panel's current position" % [scene.resource_path, unit.name])

			var chosen_edge := _edge_name(trace.to_point, rect)
			var routed_edge := _actual_edge_of_route(trace.from_point, trace.to_point, trace.trunk_dir, trace.bend_start)
			assert_eq(routed_edge, chosen_edge,
				"%s/%s: the route actually drawn to to_point must arrive on the edge to_point sits on" % [scene.resource_path, unit.name])

			var pts := TraceRouter.compute_trace_points(trace.from_point, trace.to_point,
				TraceRouter.Style.PCB, {"trunk": trace.bend_start, "trunk_dir": trace.trunk_dir})
			assert_eq(pts[pts.size() - 1], trace.to_point,
				"%s/%s: trace must terminate exactly at its own to_point" % [scene.resource_path, unit.name])
			for p in pts:
				assert_false(FanAnchor.is_inside(p, rect),
					"%s/%s: no route point may overshoot into the panel" % [scene.resource_path, unit.name])


func test_every_fan_unit_carries_the_fan_unit_group() -> void:
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		var found_any := false
		for n in inst.find_children("*", "FanUnit", true, false):
			found_any = true
			assert_true(n.is_in_group(&"fan_unit"),
				"%s: %s must carry the fan_unit group (bindings resolve by group, not NodePath)" % [scene.resource_path, n.name])
		assert_true(found_any, "%s should contain at least one FanUnit" % scene.resource_path)
