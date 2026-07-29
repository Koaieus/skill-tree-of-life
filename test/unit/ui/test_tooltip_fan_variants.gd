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


# --- #307 A/B: clock pins are handed out in left-to-right order ---------------

func _tree_order_units(variant: Node) -> Array[Node]:
	var out: Array[Node] = []
	for n in variant.find_children("*", "FanUnit", true, false):
		out.append(n)
	return out


func test_fan_order_is_angular_around_the_node_in_every_variant() -> void:
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		var ordered: Array[Node] = (inst as FanAnchorDriver).units_in_fan_order()
		assert_gt(ordered.size(), 1, "%s should have several units" % scene.resource_path)
		for i in range(ordered.size() - 1):
			assert_lt(FanAnchorDriver.fan_sort_angle(ordered[i]), FanAnchorDriver.fan_sort_angle(ordered[i + 1]),
				"%s: %s must sort left of %s" % [scene.resource_path, ordered[i].name, ordered[i + 1].name])


func test_owned_core_fan_order_is_not_tree_order() -> void:
	# The load-bearing reason units_in_fan_order() exists: the variants are
	# inherited scenes, so tree order puts the newest unit LAST regardless of
	# where its panel sits. If this ever coincides again the sort is still
	# correct — but the hazard it guards is real today, so assert it.
	var inst := _instantiate(_OWNED_CORE)
	var tree_names := _tree_order_units(inst).map(func(n: Node) -> String: return n.name)
	var fan_names: Array = (inst as FanAnchorDriver).units_in_fan_order().map(func(n: Node) -> String: return n.name)
	assert_ne(tree_names, fan_names,
		"owned_core's tree order differs from its spatial order — that's what the sort is for")


func test_pin_origins_run_left_to_right() -> void:
	# Pin ORDER only. This is what units_in_fan_order() guarantees: two traces
	# never swap sides at the node itself. It says nothing about whether their
	# routes cross further out — see the crossing test below, which is the one
	# that actually measures that.
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		await get_tree().process_frame
		var driver := inst as FanAnchorDriver
		var ordered: Array[Node] = driver.units_in_fan_order()
		var xs: Array[float] = []
		for unit in ordered:
			var trace: FanTrace = unit.get_node_or_null("%Trace")
			# Back to variant space — from_point is trace-local.
			xs.append(trace.from_point.x + trace.position.x + (unit as Node2D).position.x)
		for i in range(xs.size() - 1):
			assert_lt(xs[i], xs[i + 1],
				"%s: pin %d must sit left of pin %d (%s)" % [scene.resource_path, i, i + 1, xs])


func _route_in_variant_space(unit: Node) -> PackedVector2Array:
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	var pts := TraceRouter.compute_trace_points(trace.from_point, trace.to_point,
		TraceRouter.Style.PCB, {
			"trunk": trace.bend_start, "trunk_dir": trace.trunk_dir,
			"trunk_px": trace.trunk_length,
		})
	var offset: Vector2 = trace.position + (unit as Node2D).position
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + offset)
	return out


func _crossings(variant: Node) -> int:
	var routes: Array[PackedVector2Array] = []
	for unit in (variant as FanAnchorDriver).units_in_fan_order():
		routes.append(_route_in_variant_space(unit))
	var n := 0
	for i in range(routes.size()):
		for j in range(i + 1, routes.size()):
			for a in range(routes[i].size() - 1):
				for b in range(routes[j].size() - 1):
					var p1 := routes[i][a]
					var p2 := routes[i][a + 1]
					var q1 := routes[j][b]
					var q2 := routes[j][b + 1]
					# Shared endpoints are touching, not crossing.
					if p1.is_equal_approx(q1) or p1.is_equal_approx(q2) \
							or p2.is_equal_approx(q1) or p2.is_equal_approx(q2):
						continue
					if Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null:
						n += 1
	return n


## Measures ACTUAL polyline intersections, not pin order — the previous version
## of this test was named "...and never cross" while only checking that pin
## x-coordinates were monotonic, which passes with crossings present.
##
## Sorting the fan ANGULARLY (rather than by panel x) removed both structural
## crossings — a panel can sit further left while being angularly nearer to
## vertical, and x-order then starts the two outermost traces on each other's
## side. See FanAnchorDriver.fan_sort_angle.
##
## What survives is a placement detail, not a structural one: IdChip's panel
## sits ~17px right of centre while its pin is at 12 o'clock, so its closing
## diagonal clips Core's trunk. A hand-authored pass (nudging the panel, or its
## per-unit `bend_start`) closes it — which is why this guards the count rather
## than asserting zero.
func test_route_crossings_do_not_increase() -> void:
	var known := {
		_UNOWNED: 0,    # ordering guarantees it
		_OWNED: 0,      # was 1 before angular ordering
		_OWNED_CORE: 1, # IdChip's panel offset clips Core's trunk — authoring
	}
	for scene in [_UNOWNED, _OWNED, _OWNED_CORE]:
		var inst := _instantiate(scene)
		await get_tree().process_frame
		assert_lte(_crossings(inst), int(known[scene]),
			"%s: route crossings must not increase beyond the known %d" % [scene.resource_path, known[scene]])


func test_the_unowned_variant_is_genuinely_crossing_free() -> void:
	var inst := _instantiate(_UNOWNED)
	await get_tree().process_frame
	assert_eq(_crossings(inst), 0, "unowned's three traces must never cross")
