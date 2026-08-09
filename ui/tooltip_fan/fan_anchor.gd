## Tooltip V2 (#226) — pure geometry helper implementing Decision 4 of the
## swarmable spec: the derived trace terminus.
##
## `TraceRouter._pcb`'s closing leg is ALWAYS exactly cardinal (one axis lands
## flush on `to`). That guarantee is what makes the panel edge a line arrives
## at fully determined by the closing leg's direction, rather than something
## an author has to place by hand:
##
##   arriving rightward (closing leg moves +x) -> LEFT edge centre
##   arriving leftward  (closing leg moves -x) -> RIGHT edge centre
##   arriving downward  (closing leg moves +y) -> TOP edge centre
##   arriving upward    (closing leg moves -y) -> BOTTOM edge centre
##
## So panel POSITION is the only authored quantity: [method derive_anchor]
## recomputes which edge + where on that edge every time it's called, from
## `from`, the panel's rect, and the router params already authored on the
## [FanTrace] ([member FanTrace.trunk_dir] / [member FanTrace.bend_start]).
## Move the panel in the editor, call this again next frame (see
## `fan_anchor_driver.gd`), and the anchor — and the edge it sits on — updates
## with zero re-authoring.
##
## SELF-CONSISTENCY, not a one-shot guess: the edge nearest the panel's
## CENTRE is only a candidate. Moving `to` from the centre to that edge's
## point changes `rem` (the remainder TraceRouter's own PCB math travels
## after the diagonal), which can flip which axis is actually dominant once
## you're AT the edge instead of at the centre — the "went too far and the
## line still swaps orientation" bug this decision exists to kill. So
## [method derive_anchor] asks [TraceRouter] itself (never a re-derived
## approximation of its math) what the ACTUAL closing leg of the route TO
## each candidate looks like, and iterates candidate -> actual -> candidate
## until they agree. Verified against a real shipped unit (#226's NodeStats
## panel) that a centre-only guess gets wrong.
class_name FanAnchor
extends RefCounted

enum Edge { LEFT, RIGHT, TOP, BOTTOM }

## Which way a trace is REQUIRED to enter its panel, authored per unit
## ([member FanUnit.arrival_axis]).
##
## [code]AUTO[/code] forces nothing — it is [method derive_anchor]'s existing
## behaviour verbatim, and the default everywhere. The other two are a
## constraint the author states, which [method solve_route] then satisfies by
## solving for a trunk length (see its doc for why that's exact rather than a
## nudge).
enum Axis { AUTO, HORIZONTAL, VERTICAL }

## Shortest closing leg a FORCED arrival is allowed to settle for, in pixels.
## The constraint alone only needs the arrival axis to *win*, which at the
## boundary means winning by a fraction of a pixel and reading as a corner. This
## is the margin that keeps a forced arrival visibly perpendicular.
const MIN_ARRIVAL_LEG := 12.0

## Bounds the candidate<->actual iteration below. Two edges are ever in play
## (the tie is always between one horizontal and one vertical candidate), so
## a fixed point — when one exists — is found within 2 tries; further tries
## only exist to surface a genuine 2-cycle oscillation deterministically
## instead of by accident of loop position.
const _MAX_ITER := 4


## Solves one unit's whole route: WHERE it lands on the panel and HOW LONG its
## trunk runs. Returns `{anchor: Vector2, trunk_px: float, edge: Edge}`.
##
## This is the entry point [FanAnchorDriver] uses; [method derive_anchor] is the
## `AUTO` half of it, kept as its own function because it is also the pure
## anchor-only question a dozen tests ask directly.
##
## `params` is a [TraceRouter] param dict (see [method FanTrace.route_params]) —
## only `trunk_dir` and `trunk` are read. **Its `trunk_px` is ignored**: trunk
## length is an OUTPUT here. That's what makes re-solving a fixed point, since
## the solver never reads back the value the driver wrote last frame.
##
## `desired_trunk_px` is the author's preference ([member FanUnit.trunk_length],
## 0 = "use the bend fraction"). Under a forced axis it is a preference WITHIN
## the constraint — clamped, not honoured blindly.
##
## [b]Why forcing an axis is exact, not a nudge.[/b] After a trunk of length L,
## `_pcb`'s remainders are `span - L` along the trunk axis and `perp` across it,
## and it closes along whichever is larger. So the arrival axis is a pure
## inequality in L — perpendicular-to-trunk arrival iff `L > span - perp`, along
## trunk iff `L < span - perp`. Solving it means the EDGE is determined outright
## (the one facing `from`), so there is no candidate->actual iteration and the
## 2-cycle [method derive_anchor] documents cannot occur at all.
##
## Falls back to `AUTO` with a warning when the constraint is unsatisfiable: a
## panel with almost no sideways offset can't be entered horizontally, one
## almost beside the pin can't be entered vertically, and neither can be entered
## at all from a `from` that isn't on the trunk's side of it.
static func solve_route(from: Vector2, panel_rect: Rect2, params: Dictionary, axis: Axis = Axis.AUTO, slide: float = 0.5, desired_trunk_px: float = 0.0) -> Dictionary:
	var trunk_dir: Vector2 = params.get("trunk_dir", Vector2(0.0, -1.0))
	if trunk_dir == Vector2.ZERO:
		trunk_dir = Vector2(0.0, -1.0)
	trunk_dir = trunk_dir.normalized()
	var trunk_frac: float = params.get("trunk", FanTrace.PHI_FRACTION)

	if axis == Axis.AUTO:
		var derived := derive_anchor(from, panel_rect, trunk_dir, trunk_frac, slide)
		return {
			"anchor": derived,
			"trunk_px": desired_trunk_px,
			"edge": _edge_of_route_to(from, derived, trunk_dir, trunk_frac),
		}

	var want_horizontal := axis == Axis.HORIZONTAL
	var centre := panel_rect.get_center()
	var edge: FanAnchor.Edge
	if want_horizontal:
		edge = Edge.LEFT if from.x < centre.x else Edge.RIGHT
	else:
		edge = Edge.BOTTOM if from.y > centre.y else Edge.TOP
	var anchor := _point_on_edge(edge, panel_rect, slide)

	# Decompose the run in the trunk's own frame: `span` along it, `perp` across.
	var d := anchor - from
	var perp_dir := Vector2(-trunk_dir.y, trunk_dir.x)
	var span := d.dot(trunk_dir)
	var perp := absf(d.dot(perp_dir))
	# The requested axis is the trunk's own only when trunk and request line up
	# (a vertical trunk asked for a VERTICAL arrival); otherwise it's the
	# perpendicular one. Written out rather than assuming an upward trunk, since
	# `Roots` already points the other way and a radial variant may point anywhere.
	var trunk_is_vertical := absf(trunk_dir.y) >= absf(trunk_dir.x)
	var arrival_is_perp := want_horizontal == trunk_is_vertical

	var lo := 0.0
	var hi := span
	if arrival_is_perp:
		lo = span - perp + MIN_ARRIVAL_LEG
	else:
		hi = span - perp - MIN_ARRIVAL_LEG
	if span <= 0.0 or lo > hi:
		push_warning(("FanAnchor: %s arrival is unsatisfiable for panel %s from %s "
			% ["horizontal" if want_horizontal else "vertical", panel_rect, from])
			+ "(span %.1f, perpendicular offset %.1f) — falling back to AUTO. Move the panel further %s."
				% [span, perp, "sideways" if arrival_is_perp else "along the trunk"])
		return solve_route(from, panel_rect, params, Axis.AUTO, slide, desired_trunk_px)

	var desired := desired_trunk_px if desired_trunk_px > 0.0 else trunk_frac * span
	return {"anchor": anchor, "trunk_px": clampf(desired, maxf(lo, 0.0), hi), "edge": edge}


## Returns the point on `panel_rect`'s boundary where a PCB trace from `from`
## (leaving along `trunk_dir`, breaking to 45° at `trunk_frac` of the trunk
## axis) ACTUALLY arrives, per the route [TraceRouter] itself would draw to
## get there — not an approximation of it. See the class doc for why a
## single guess from the rect's centre isn't enough.
##
## This is [method solve_route]'s `AUTO` case: it forces nothing and derives
## everything, which is what every unit does unless it authors an
## [enum Axis].
static func derive_anchor(from: Vector2, panel_rect: Rect2, trunk_dir: Vector2, trunk_frac: float = FanTrace.PHI_FRACTION, slide: float = 0.5) -> Vector2:
	var edge := _edge_of_route_to(from, panel_rect.get_center(), trunk_dir, trunk_frac)
	for _i in range(_MAX_ITER):
		var anchor := _point_on_edge(edge, panel_rect, slide)
		var actual := _edge_of_route_to(from, anchor, trunk_dir, trunk_frac)
		if actual == edge:
			return anchor
		edge = actual
	# Two candidate edges kept disagreeing with each other's own routed
	# result — a genuine 2-cycle (only possible right at the tie boundary,
	# where the panel needs more separation from the node on one axis). Land
	# on whichever candidate this loop last computed rather than looping
	# forever or crashing; a human moving the panel a few pixels resolves it.
	#
	# At `slide` 0 or 1 the anchor IS a corner, which belongs to both edges at
	# once — so a 2-cycle there is not a failure to resolve, it's two equally
	# correct answers naming the same point. The fallback lands on the right
	# place either way.
	#
	# Anywhere else the returned point is still ON a real edge and the route
	# still reaches it — what got traded away is PERPENDICULARITY: the closing
	# leg runs alongside that edge instead of into it. That's tolerated rather
	# than warned about, because it's a legitimate resting place for synthetic
	# geometry (`test_fan_anchor.gd`'s up-and-right quadrant case lands here and
	# asserts the edge is still the correct one). What must not tolerate it is a
	# SHIPPED unit — `test_tooltip_fan_variants.gd`'s self-consistency test is
	# the guard, and the fix there is authoring, not code: raise the unit's
	# `anchor_slide` toward the corner the trace approaches from (the reachable
	# window shrinks to that end of the edge), or give the panel more
	# separation from the pin on the tied axis.
	return _point_on_edge(edge, panel_rect, slide)


## Asks [TraceRouter] for the real route to `to` and reads off which edge its
## closing leg (the last segment — always cardinal, per `_pcb`'s own
## guarantee) arrives at. The single source of truth stays in TraceRouter;
## this never re-derives the diagonal/trunk math itself.
static func _edge_of_route_to(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float) -> FanAnchor.Edge:
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {
		"trunk": trunk_frac,
		"trunk_dir": trunk_dir,
	})
	var leg := pts[pts.size() - 1] - pts[pts.size() - 2] if pts.size() >= 2 else Vector2.ZERO
	if absf(leg.x) >= absf(leg.y):
		return Edge.LEFT if leg.x >= 0.0 else Edge.RIGHT
	return Edge.TOP if leg.y >= 0.0 else Edge.BOTTOM


## Where on `edge` the anchor sits. `slide` runs 0 → 1 along the edge in
## reading order — top→bottom for the vertical (LEFT/RIGHT) edges, left→right
## for the horizontal (TOP/BOTTOM) ones. 0.5 is the edge centre, i.e. the
## behaviour before `slide` existed; 0 and 1 are the edge's two corners.
##
## Which edge is derived (that's what guarantees the arrival leg is
## perpendicular to it); only WHERE along it is authored. So a unit that moves
## across the fan's centreline flips edges automatically and its slide stays
## meaningful — nothing needs re-authoring.
static func _point_on_edge(edge: FanAnchor.Edge, rect: Rect2, slide: float = 0.5) -> Vector2:
	var t := clampf(slide, 0.0, 1.0)
	var far := rect.position + rect.size
	match edge:
		Edge.LEFT:
			return Vector2(rect.position.x, lerpf(rect.position.y, far.y, t))
		Edge.RIGHT:
			return Vector2(far.x, lerpf(rect.position.y, far.y, t))
		Edge.TOP:
			return Vector2(lerpf(rect.position.x, far.x, t), rect.position.y)
		_:
			return Vector2(lerpf(rect.position.x, far.x, t), far.y)


## The panel rect in the coordinate space `panel.position` lives in (i.e. its
## parent's local space — the same space [FanTrace.to_point] is authored in).
## Reads the skin Control's own (position, size) rather than assuming a
## symmetric envelope, so an off-centre skin still measures correctly.
##
## Sums every Control ancestor's `position` between the skin and `panel`
## rather than assuming the skin is a direct child — `panel_base.tscn` nests
## it under a `PanelContainer` (the auto-hugging envelope) alongside its
## `MarginContainer` sibling, one level deeper than [method FanPanel.get_skin]
## used to require.
static func panel_rect_of(panel: FanPanel) -> Rect2:
	var skin := panel.get_skin()
	if skin == null:
		return Rect2(panel.position, Vector2.ZERO)
	var offset := Vector2.ZERO
	var node: Node = skin
	while node != null and node != panel:
		if node is Control:
			offset += (node as Control).position
		node = node.get_parent()
	return Rect2(panel.position + offset, skin.size)


## True if `point` lies strictly inside `rect` — used by tests to assert a
## trace's intermediate points never overshoot into (or past) the panel it
## terminates at. Points exactly on the boundary (the anchor itself) are not
## "inside".
static func is_inside(point: Vector2, rect: Rect2) -> bool:
	return point.x > rect.position.x and point.x < rect.position.x + rect.size.x \
		and point.y > rect.position.y and point.y < rect.position.y + rect.size.y
