extends GutTest

## Tooltip V2 (#226/#314) — structural checks on `fan.tscn`, the ONE fan scene
## that replaced the three occupancy-class variants: the reserved HP band
## (Decision 3), no-two-panels-overlap, the z-sandwich (HoloPanel z=-1 /
## content z=0 / ScanlineOverlay z=+1), and trace self-consistency. All
## geometric, none a screenshot — see #226's report for what stays
## editor-judgment (final placement/prettiness) vs. what's asserted here.
##
## The clock-pin spread is now a function of how many units PARTICIPATE
## (#314), so the crossing checks come in two flavours: the full six-member fan
## a core node gets, and the subset an unowned node gets. Both have to stay
## clean — the second one is the common case.

const _FAN := preload("res://ui/tooltip_fan/fan.tscn")

## Decision 3: no panel may occupy y in [-70,-28], |x| <= 45 in node-local
## space (the reserved HP band above the node's HealthBar/CoreHealthBar).
const _BAND := Rect2(Vector2(-45.0, -70.0), Vector2(90.0, 42.0))

## The units a HAND-AUTHORED, UNOWNED node's fan gates out: Owner needs an
## owning entity, Core needs to be one, and ProcgenDebug (#292) needs a
## `procgen_footprint` meta that only `GraphProcgen` stamps. Kept as names rather
## than derived from `has_content()` so these tests state the expectation instead
## of restating the implementation.
##
## A *procgen* unowned node would additionally show ProcgenDebug; the fixture
## here is the dev-sandbox / test-graph case.
const _UNOWNED_SUPPRESSED := ["Owner", "Core", "ProcgenDebug"]


func _panel_rects(fan: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for n in fan.find_children("*", "FanPanel", true, false):
		var panel := n as FanPanel
		# Global-in-fan-space rect: FanPanel nodes may be nested a level
		# deep (inside a FanUnit), so fold the unit's own position in too.
		var unit_pos: Vector2 = panel.get_parent().position if panel.get_parent() is Node2D else Vector2.ZERO
		var rect := FanAnchor.panel_rect_of(panel)
		rect.position += unit_pos
		out.append(rect)
	return out


func _instantiate() -> Node:
	var inst := _FAN.instantiate()
	add_child(inst)
	autofree(inst)
	return inst


## Gates the named units out and re-derives, so the geometry under test is the
## one that ships for a node those panels don't apply to. Uses
## [method FanAnchorDriver.refresh] rather than waiting frames because refresh
## SNAPS the pins — an eased read would land mid-slide and assert nothing.
func _suppress(fan: Node, unit_names: Array) -> void:
	for unit_name in unit_names:
		var unit := fan.find_child(String(unit_name), true, false) as FanUnit
		assert_not_null(unit, "fan.tscn should carry a %s unit" % unit_name)
		unit.participating = false
		unit.pin_angle = NAN
	(fan as FanAnchorDriver).refresh()


## Gates units out WITHOUT the snap [method _suppress] performs — needed by the
## easing tests, which have to observe the slide the snap would skip.
func _gate_out_without_refresh(fan: Node, unit_names: Array) -> void:
	for unit_name in unit_names:
		var unit := fan.find_child(String(unit_name), true, false) as FanUnit
		unit.participating = false


func test_no_panel_occupies_the_reserved_hp_band() -> void:
	var inst := _instantiate()
	for rect in _panel_rects(inst):
		assert_false(rect.intersects(_BAND),
			"panel rect %s must not intersect the reserved HP band %s" % [rect, _BAND])


func test_no_two_panels_overlap() -> void:
	var inst := _instantiate()
	var rects := _panel_rects(inst)
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]),
				"panel %d overlaps panel %d (%s vs %s)" % [i, j, rects[i], rects[j]])


func test_z_sandwich_is_set_up_on_every_content_panel() -> void:
	# Structural assertion ONLY — see the #226 report: nobody has visually
	# confirmed this renders as a hologram-with-scanlines-on-top. This proves
	# the z_index values are wired correctly, nothing about pixels.
	var inst := _instantiate()
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


## #314: one scene carries every panel. Pre-#314 this was three scenes with
## Owner appended by `owned.tscn` and Core by `owned_core.tscn`; the equivalent
## assertion now is that the single fan holds the full set, since a missing unit
## can no longer be explained away as "wrong variant".
func test_the_fan_carries_every_content_panel() -> void:
	var inst := _instantiate()
	var names: Array = inst.find_children("*", "FanUnit", true, false).map(
		func(n: Node) -> String: return n.name)
	for expected in ["IdChip", "NodeStats", "Addons", "Owner", "Core", "ProcgenDebug"]:
		assert_true(names.has(expected), "fan.tscn must mount the %s unit (have %s)" % [expected, names])
	assert_not_null(inst.find_child("Roots", true, false),
		"fan.tscn must mount the GrantedModifiersRoot")


func _edge_name(anchor: Vector2, rect: Rect2) -> String:
	if is_equal_approx(anchor.x, rect.position.x):
		return "left"
	if is_equal_approx(anchor.x, rect.position.x + rect.size.x):
		return "right"
	if is_equal_approx(anchor.y, rect.position.y):
		return "top"
	return "bottom"


## The route a trace ACTUALLY draws, rebuilt through the trace's own
## [method FanTrace.route_params] — never a hand-built param dict. A copy that
## omits `trunk_px` describes a different line than the one on screen, and since
## the driver now SOLVES that value for any unit with an `arrival_axis`, such a
## copy would quietly assert against a route nobody draws.
func _route_of(trace: FanTrace) -> PackedVector2Array:
	return TraceRouter.compute_trace_points(
		trace.from_point, trace.to_point, TraceRouter.Style.PCB, trace.route_params())


func _actual_edge_of_route(trace: FanTrace) -> String:
	var pts := _route_of(trace)
	var leg := pts[pts.size() - 1] - pts[pts.size() - 2]
	if absf(leg.x) >= absf(leg.y):
		return "left" if leg.x >= 0.0 else "right"
	return "top" if leg.y >= 0.0 else "bottom"


## Decision 4 must hold for every shipped unit, not just synthetic
## quadrants: (1) the trace's CURRENT `to_point` must equal what
## [FanAnchor.solve_route] derives fresh from the panel's live position —
## i.e. nothing here is a stale/hand-authored value masquerading as derived —
## and (2) the route TraceRouter actually draws to that point must arrive on
## the SAME edge the point sits on (the exact bug review caught: a
## centre-only guess can name an edge the drawn route doesn't agree with).
## `no-overshoot` alone can't catch that bug — a leg can slide along a
## panel's edge without ever reading as "inside" it — so it isn't asserted
## here as a substitute for the edge check.
##
## PENDING #362 — known broken, parked (FOCUS lane E item 7) while it stays
## collected, so the suite baseline is green and any NEW red is unambiguous.
##
## Do NOT infer a direction from #362's title: the issue was filed about
## `test_no_two_panels_overlap` "failing in isolation", but THIS function is a
## different failure under the same issue — it was red in a full-suite run
## (audit 2026-08-13 baseline, `00-brief.md`) while the overlap test now passes
## in isolation. The order-dependence is real; which way round it cuts for this
## function has not been measured.
##
## `pending()` does not short-circuit in GUT, hence the explicit `return`.
func test_every_fan_traces_terminus_is_self_consistent() -> void:
	pending("#362 — run-order dependent, fails in isolation")
	return
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	for unit in inst.find_children("*", "FanUnit", true, false):
		var trace: FanTrace = unit.get_node_or_null("%Trace")
		var panel: FanPanel = unit.get_node_or_null("%Panel")
		if trace == null or panel == null:
			continue
		var rect := FanAnchor.panel_rect_of(panel)
		var fan_unit := unit as FanUnit
		var solved := FanAnchor.solve_route(trace.from_point, rect, trace.route_params(),
			fan_unit.arrival_axis, fan_unit.anchor_slide, fan_unit.trunk_length)
		assert_eq(trace.to_point, solved.anchor,
			"%s: to_point must equal a fresh solve_route() of the panel's current position" % unit.name)
		assert_almost_eq(trace.trunk_length, float(solved.trunk_px), 0.01,
			"%s: the trace's trunk length must be the solver's, not a stale write" % unit.name)

		var chosen_edge := _edge_name(trace.to_point, rect)
		var routed_edge := _actual_edge_of_route(trace)
		assert_eq(routed_edge, chosen_edge,
			"%s: the route actually drawn to to_point must arrive on the edge to_point sits on" % unit.name)

		var pts := _route_of(trace)
		assert_eq(pts[pts.size() - 1], trace.to_point,
			"%s: trace must terminate exactly at its own to_point" % unit.name)
		for p in pts:
			assert_false(FanAnchor.is_inside(p, rect),
				"%s: no route point may overshoot into the panel" % unit.name)


## An authored [member FanUnit.arrival_axis] is a promise about the SHIPPED
## line, not just about the solver: whatever the driver ends up writing, the
## last segment TraceRouter draws must run on the requested axis. This is what
## makes the knob trustworthy for authoring — you set it and stop checking.
func test_units_with_a_forced_arrival_axis_actually_arrive_on_that_axis() -> void:
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	var checked := 0
	for unit in inst.find_children("*", "FanUnit", true, false):
		var fan_unit := unit as FanUnit
		if fan_unit.arrival_axis == FanAnchor.Axis.AUTO:
			continue
		var trace: FanTrace = unit.get_node_or_null("%Trace")
		var pts := _route_of(trace)
		var leg := pts[pts.size() - 1] - pts[pts.size() - 2]
		checked += 1
		if fan_unit.arrival_axis == FanAnchor.Axis.HORIZONTAL:
			assert_gt(absf(leg.x), absf(leg.y),
				"%s: HORIZONTAL arrival must close on x (leg %s)" % [unit.name, leg])
		else:
			assert_gt(absf(leg.y), absf(leg.x),
				"%s: VERTICAL arrival must close on y (leg %s)" % [unit.name, leg])
		assert_gte(leg.length(), FanAnchor.MIN_ARRIVAL_LEG - 0.01,
			"%s: a forced arrival must clear MIN_ARRIVAL_LEG, not win by a hair" % unit.name)
	assert_gt(checked, 0, "no shipped unit authors an arrival_axis — this test would be vacuous")


func test_every_fan_unit_carries_the_fan_unit_group() -> void:
	var inst := _instantiate()
	var found_any := false
	for n in inst.find_children("*", "FanUnit", true, false):
		found_any = true
		assert_true(n.is_in_group(&"fan_unit"),
			"%s must carry the fan_unit group (bindings resolve by group, not NodePath)" % n.name)
	assert_true(found_any, "fan.tscn should contain at least one FanUnit")


# --- #307 A/B: clock pins are handed out in left-to-right order ---------------

func test_fan_order_is_angular_around_the_node() -> void:
	var inst := _instantiate()
	var ordered: Array[Node] = (inst as FanAnchorDriver).units_in_fan_order()
	assert_gt(ordered.size(), 1, "the fan should have several units")
	for i in range(ordered.size() - 1):
		assert_lt(FanAnchorDriver.fan_sort_angle(ordered[i]), FanAnchorDriver.fan_sort_angle(ordered[i + 1]),
			"%s must sort left of %s" % [ordered[i].name, ordered[i + 1].name])


func _pin_xs(fan: Node) -> Array[float]:
	var xs: Array[float] = []
	for unit in (fan as FanAnchorDriver).units_in_fan_order():
		var trace: FanTrace = unit.get_node_or_null("%Trace")
		# Back to fan space — from_point is trace-local.
		xs.append(trace.from_point.x + trace.position.x + (unit as Node2D).position.x)
	return xs


func test_pin_origins_run_left_to_right() -> void:
	# Pin ORDER only. This is what units_in_fan_order() guarantees: two traces
	# never swap sides at the node itself. It says nothing about whether their
	# routes cross further out — see the crossing tests below, which are the
	# ones that actually measure that.
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	var xs := _pin_xs(inst)
	for i in range(xs.size() - 1):
		assert_lt(xs[i], xs[i + 1], "pin %d must sit left of pin %d (%s)" % [i, i + 1, xs])


func test_pin_origins_still_run_left_to_right_with_units_suppressed() -> void:
	# The redistribution must not reorder anybody: gating two units out changes
	# every survivor's slot, and getting that wrong would start two traces on
	# each other's side of the node.
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	_suppress(inst, _UNOWNED_SUPPRESSED)
	var xs := _pin_xs(inst)
	assert_eq(xs.size(), 3, "an unowned node's fan should place three pins")
	for i in range(xs.size() - 1):
		assert_lt(xs[i], xs[i + 1], "pin %d must sit left of pin %d (%s)" % [i, i + 1, xs])


func _route_in_fan_space(unit: Node) -> PackedVector2Array:
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	var pts := _route_of(trace)
	var offset: Vector2 = trace.position + (unit as Node2D).position
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + offset)
	return out


func _crossings(fan: Node) -> int:
	var routes: Array[PackedVector2Array] = []
	for unit in (fan as FanAnchorDriver).units_in_fan_order():
		routes.append(_route_in_fan_space(unit))
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


## Measures ACTUAL polyline intersections, not pin order.
##
## What survives is a placement detail, not a structural one: IdChip's panel
## sits ~17px right of centre while its pin is near 12 o'clock, so its closing
## diagonal clips Core's trunk. A hand-authored pass (nudging the panel, or its
## per-unit `bend_start`) closes it — which is why this guards the count rather
## than asserting zero.
func test_route_crossings_do_not_increase_on_the_full_fan() -> void:
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	assert_lte(_crossings(inst), 1, "route crossings must not increase beyond the known 1")


## The common case (#226's own note: unowned nodes dominate at ~2.2L owned out
## of a ~150-node graph) must be genuinely clean, not merely no-worse. This is
## the pre-#314 `unowned.tscn` guarantee, re-expressed against the mechanism
## that replaced it: same three panels, reached by suppression rather than by a
## separate scene.
func test_an_unowned_nodes_fan_is_genuinely_crossing_free() -> void:
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	_suppress(inst, _UNOWNED_SUPPRESSED)
	assert_eq(_crossings(inst), 0, "an unowned node's three traces must never cross")


# --- #314: the clock face is shared out among participating units only --------

func _angle_of_pin(unit: Node) -> float:
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	var pin: Vector2 = trace.from_point + trace.position + (unit as Node2D).position
	return rad_to_deg(atan2(pin.x, -pin.y))


func test_suppressing_units_tightens_the_spread_onto_the_survivors() -> void:
	# Three participating units get 11/12/1 — the same slots three units would
	# get in any other configuration. The reversal of the old "a suppressed
	# panel keeps its pin" rule, stated as an assertion: if pins were held open,
	# the survivors would sit at three of six wider slots instead.
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	_suppress(inst, _UNOWNED_SUPPRESSED)
	var angles: Array[float] = []
	for unit in (inst as FanAnchorDriver).units_in_fan_order():
		angles.append(_angle_of_pin(unit))
	assert_eq(angles.size(), 3, "three units should be participating")
	assert_almost_eq(angles[0], -30.0, 0.5, "11 o'clock")
	assert_almost_eq(angles[1], 0.0, 0.5, "12 o'clock")
	assert_almost_eq(angles[2], 30.0, 0.5, "1 o'clock")


func test_a_suppressed_unit_is_excluded_from_the_pin_order() -> void:
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	var before: int = (inst as FanAnchorDriver).units_in_fan_order().size()
	_suppress(inst, ["Core"])
	var after: int = (inst as FanAnchorDriver).units_in_fan_order().size()
	assert_eq(after, before - 1, "gating one unit out must drop exactly one pin")


func test_units_participate_by_default_so_the_editor_shows_the_full_spread() -> void:
	# The driver has to be useful with fan.tscn open standalone, where no
	# coordinator exists to classify anything. That only holds if the default
	# is "in".
	var inst := _instantiate()
	for unit in inst.find_children("*", "FanUnit", true, false):
		assert_true((unit as FanUnit).participating,
			"%s must default to participating" % unit.name)
	assert_eq((inst as FanAnchorDriver).units_in_fan_order().size(), 6,
		"all six panel-bearing units should take a pin by default")


# --- #314: slot changes are eased, not snapped -------------------------------

## The unit whose slot actually MOVES when Owner and Core are gated out.
##
## Not IdChip: it sits dead centre on 12 o'clock in both the full spread and the
## three-pin one, so easing is unobservable there. NodeStats is the outermost
## survivor — it moves from the left end of the full spread to the -30 degree end
## of a three-pin one.
const _SLIDING_UNIT := "NodeStats"


## Where `unit` is HEADED once the participating set has settled, computed the
## same way the driver computes it. Read after gating, before any frame elapses.
func _target_angle_of(fan: Node, unit: FanUnit) -> float:
	var driver := fan as FanAnchorDriver
	var ordered := driver.units_in_fan_order()
	return FanAnchorDriver.pin_angle(
		ordered.find(unit), ordered.size(), driver.pin_step_degrees, driver.max_arc_degrees)


func test_a_slot_change_eases_rather_than_snapping() -> void:
	# The whole point of the easing: when a panel ignites, its neighbours must
	# SLIDE. One frame after the participating set changes, a moved pin must sit
	# strictly between where it was and where it's going.
	var inst := _instantiate()
	var driver := inst as FanAnchorDriver
	driver.refresh()
	# Slow the slide right down so a single frame can't complete it regardless
	# of how long that frame took on a loaded headless runner.
	driver.pin_slide_rate = 1.0
	var unit := inst.find_child(_SLIDING_UNIT, true, false) as FanUnit
	var start: float = unit.pin_angle
	_gate_out_without_refresh(inst, _UNOWNED_SUPPRESSED)
	var target := _target_angle_of(inst, unit)
	assert_ne(start, target, "this fixture needs %s's slot to actually move" % _SLIDING_UNIT)
	# process_frame fires before Node._process() runs for that same frame, so
	# one await can resume before the driver has actually ticked once.
	await get_tree().process_frame
	await get_tree().process_frame
	var mid: float = unit.pin_angle
	assert_ne(mid, target, "one frame must not land the pin on its target — that would be a snap")
	assert_true(absf(mid - target) < absf(start - target),
		"the pin must have moved TOWARD its target (start %f, mid %f, target %f)" % [start, mid, target])


func test_refresh_snaps_the_pin_all_the_way() -> void:
	# refresh() is the tests' and the editor's entry point; it must not leave
	# geometry mid-slide, or nothing downstream can assert against it.
	var inst := _instantiate()
	var driver := inst as FanAnchorDriver
	driver.refresh()
	driver.pin_slide_rate = 1.0
	var unit := inst.find_child(_SLIDING_UNIT, true, false) as FanUnit
	_gate_out_without_refresh(inst, _UNOWNED_SUPPRESSED)
	var target := _target_angle_of(inst, unit)
	driver.refresh()
	assert_almost_eq(unit.pin_angle, target, 0.0001, "refresh() must snap, not ease")


func test_the_eased_pin_reaches_its_target_and_stops() -> void:
	# Easing must CONVERGE, not asymptote forever — the settle epsilon exists so
	# `from_point` stops being rewritten every frame for a sub-pixel gain.
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	var unit := inst.find_child(_SLIDING_UNIT, true, false) as FanUnit
	_gate_out_without_refresh(inst, _UNOWNED_SUPPRESSED)
	var target := _target_angle_of(inst, unit)
	for _i in range(120):
		await get_tree().process_frame
	assert_almost_eq(unit.pin_angle, target, 0.0001,
		"the pin must settle exactly on its slot, not near it")
