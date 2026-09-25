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

## The units a HAND-AUTHORED, UNOWNED node's fan gates out: Owner needs an
## owning entity, Core needs to be one, ProcgenDebug (#292) needs a
## `procgen_footprint` meta that only `GraphProcgen` stamps, and EffectReadout
## (#621) needs a live aura/effect actually reaching the node — this bare
## fixture carries none. Kept as names rather than derived from
## `has_content()` so these tests state the expectation instead of restating
## the implementation.
##
## A *procgen* unowned node would additionally show ProcgenDebug; the fixture
## here is the dev-sandbox / test-graph case. An unowned node CAN legitimately
## show EffectReadout in real play (a hostile aura reaching unclaimed
## territory) — it's suppressed here only because this fixture has no graph
## content to source one from, not because the panel is owned-node-only.
const _UNOWNED_SUPPRESSED := ["Owner", "Core", "ProcgenDebug", "EffectReadout"]


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


## Every panel of the real fan at zoom 1, all units participating: `refresh()`
## runs the solver to convergence, and the converged layout keeps every pair
## apart and every panel off the node + Roots obstacle.
func test_refresh_converges_the_layout_with_no_overlap_and_no_obstacle_hit() -> void:
	var inst := _instantiate()
	var driver := inst as FanAnchorDriver
	driver.refresh()
	var rects := _panel_rects(inst)
	assert_eq(rects.size(), 7, "every unit participates standalone")
	for i in range(rects.size()):
		for o in driver.obstacles():
			assert_false(rects[i].intersects(o),
				"panel %s must clear the node/Roots obstacle %s" % [rects[i], o])
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]),
				"panel %d overlaps panel %d (%s vs %s)" % [i, j, rects[i], rects[j]])


## Nothing to push against: a panel on its own converges exactly onto its
## authored rest — where the unit's `position` puts it before any solve.
func test_a_lone_panel_sits_at_its_rest() -> void:
	var inst := _instantiate()
	var unit := inst.find_child("ProcgenDebug", true, false) as FanUnit
	var panel := unit.get_node("%Panel") as FanPanel
	var authored := FanAnchor.panel_rect_of(panel).position + unit.position
	_suppress(inst, ["IdChip", "NodeStats", "Addons", "Owner", "Core", "EffectReadout"])
	var solved := FanAnchor.panel_rect_of(panel).position + unit.position
	assert_almost_eq(solved.x, authored.x, 0.1, "a lone panel must sit at its rest")
	assert_almost_eq(solved.y, authored.y, 0.1, "a lone panel must sit at its rest")


## The whole fan crowds, so some panel is pushed — but the solver's contact
## equilibrium holds every pair at least `padding` apart.
func test_a_crowded_panel_is_pushed_off_its_rest_but_never_past_padding() -> void:
	var inst := _instantiate()
	var driver := inst as FanAnchorDriver
	driver.refresh()
	var rects := _panel_rects(inst)
	var half: float = (driver.padding - 0.1) * 0.5
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].grow(half).intersects(rects[j].grow(half)),
				"panels %d and %d closer than padding (%s vs %s)" % [i, j, rects[i], rects[j]])


## The node grows with the camera zoom while panels stay screen-constant, so
## the node obstacle has to grow with it.
func test_the_node_obstacle_scales_with_zoom() -> void:
	var inst := _instantiate()
	var driver := inst as FanAnchorDriver
	driver.zoom_scale = 2.0
	driver.refresh()
	var doubled := Rect2(FanAnchorDriver.NODE_FOOTPRINT.position * 2.0,
		FanAnchorDriver.NODE_FOOTPRINT.size * 2.0)
	for rect in _panel_rects(inst):
		assert_false(rect.intersects(doubled),
			"panel %s must clear the zoom-2 node rect %s" % [rect, doubled])


## The serialization invariant: the solved position lands on `%Panel`, and a
## unit's own `position` — the authored rest, saved in `fan.tscn` — never moves.
func test_the_driver_never_writes_a_units_position() -> void:
	var inst := _instantiate()
	var driver := inst as FanAnchorDriver
	var before := {}
	for unit in inst.find_children("*", "FanUnit", true, false):
		before[unit.name] = (unit as Node2D).position
	for _frame in 60:
		driver._process(1.0 / 60.0)
	for unit in inst.find_children("*", "FanUnit", true, false):
		assert_eq((unit as Node2D).position, before[unit.name],
			"%s: the driver must never write a unit's position" % unit.name)


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
	for expected in ["IdChip", "NodeStats", "Addons", "Owner", "Core", "ProcgenDebug", "EffectReadout"]:
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
## omits `trunk_px` describes a different line than the one on screen — the
## driver writes its fan-wide `trunk_length` onto every trace — so such a copy
## would quietly assert against a route nobody draws.
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
## Checked on the CONVERGED layout (`refresh()` settles the solver first), so
## the result no longer depends on which test ran before this one.
func test_every_fan_traces_terminus_is_self_consistent() -> void:
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	for unit in (inst as FanAnchorDriver).units_in_fan_order():
		var trace: FanTrace = unit.get_node("%Trace")
		var rect := FanAnchor.panel_rect_of(unit.get_node("%Panel") as FanPanel)
		if not rect.has_area():
			continue  # unbound here (IdChip sizes to its content): no edges to name
		var fresh: Vector2 = FanAnchor.solve_route(trace.from_point, rect, trace.route_params()).anchor
		assert_almost_eq(trace.to_point.x, fresh.x, 0.01, "%s: to_point must be derived" % unit.name)
		assert_almost_eq(trace.to_point.y, fresh.y, 0.01, "%s: to_point must be derived" % unit.name)
		assert_eq(_actual_edge_of_route(trace), _edge_name(trace.to_point, rect),
			"%s: the drawn route must arrive on the edge its anchor sits on" % unit.name)


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
##
## #621 added a second, same shape: EffectReadout's pin sits at ~6 o'clock,
## far outside the other six units' ±60° arc, so [method
## FanAnchorDriver.pin_angle]'s compression (`max_arc_degrees` unchanged, `step`
## shrinks to fit the 7th slot) lands it right against whichever neighbour it
## sorts next to — Core today — and their trunks clip. Same "placement detail,
## not structural" bucket as the first one; a hand-authored nudge can close
## this too, whenever someone's doing a geometry pass on the shipped fan.
func test_route_crossings_do_not_increase_on_the_full_fan() -> void:
	var inst := _instantiate()
	(inst as FanAnchorDriver).refresh()
	assert_lte(_crossings(inst), 2, "route crossings must not increase beyond the known 2")


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
	assert_eq((inst as FanAnchorDriver).units_in_fan_order().size(), 7,
		"all seven panel-bearing units should take a pin by default")


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
	# The ease runs on delta, so give it wall-clock time, not a frame count —
	# the headless frame period is a test-hook knob and 120 frames may be 0.2 s.
	await wait_until(func() -> bool: return absf(unit.pin_angle - target) < 0.0001, 3.0)
	assert_almost_eq(unit.pin_angle, target, 0.0001,
		"the pin must settle exactly on its slot, not near it")
