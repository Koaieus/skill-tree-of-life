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
## No node dependencies, no randomness — a pure static function, exactly like
## [TraceRouter] itself. This is what the acceptance tests exercise directly.
class_name FanAnchor
extends RefCounted


## Returns the point on `panel_rect`'s boundary where a PCB trace from `from`
## (leaving along `trunk_dir`, breaking to 45° at `trunk_frac` of the trunk
## axis) arrives — the centre of whichever edge its closing leg is cardinal
## into. Mirrors the `rem` computation [TraceRouter]._pcb performs internally,
## but only far enough to learn the closing leg's dominant axis and sign; it
## does not (and must not) duplicate the diagonal/dedup logic — that stays
## the single source of truth in TraceRouter.
static func derive_anchor(from: Vector2, panel_rect: Rect2, trunk_dir: Vector2, trunk_frac: float = FanTrace.PHI_FRACTION) -> Vector2:
	var center := panel_rect.get_center()
	var dir := trunk_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0.0, -1.0)
	var d := center - from
	var trunk_len := trunk_frac * absf(d.dot(dir))
	var trunk_top := from + dir * trunk_len
	var rem := center - trunk_top

	if absf(rem.x) >= absf(rem.y):
		# Closing leg is horizontal. rem.x >= 0 means the leg still has to
		# travel in +x to reach the centre — arriving rightward — so it
		# meets the panel at its LEFT edge first. rem.x < 0 is the mirror:
		# arriving leftward, RIGHT edge.
		if rem.x >= 0.0:
			return Vector2(panel_rect.position.x, center.y)
		return Vector2(panel_rect.position.x + panel_rect.size.x, center.y)

	# Closing leg is vertical. rem.y >= 0: arriving downward -> TOP edge.
	# rem.y < 0: arriving upward -> BOTTOM edge.
	if rem.y >= 0.0:
		return Vector2(center.x, panel_rect.position.y)
	return Vector2(center.x, panel_rect.position.y + panel_rect.size.y)


## The panel rect in the coordinate space `panel.position` lives in (i.e. its
## parent's local space — the same space [FanTrace.to_point] is authored in).
## Reads the skin Control's own (position, size) rather than assuming a
## symmetric envelope, so an off-centre skin still measures correctly.
static func panel_rect_of(panel: FanPanel) -> Rect2:
	var skin := panel.get_skin()
	if skin == null:
		return Rect2(panel.position, Vector2.ZERO)
	return Rect2(panel.position + skin.position, skin.size)


## True if `point` lies strictly inside `rect` — used by tests to assert a
## trace's intermediate points never overshoot into (or past) the panel it
## terminates at. Points exactly on the boundary (the anchor itself) are not
## "inside".
static func is_inside(point: Vector2, rect: Rect2) -> bool:
	return point.x > rect.position.x and point.x < rect.position.x + rect.size.x \
		and point.y > rect.position.y and point.y < rect.position.y + rect.size.y
