@tool
class_name FanAnchorDriver
extends Node2D

## Tooltip V2 (#226) — keeps every [FanUnit]'s trace terminus derived live
## from its panel's CURRENT position (Decision 4). Attached as the root
## script of `fan.tscn` so a human dragging a panel in the editor sees the
## trace re-route immediately, without opening [TooltipFan] at all — that is
## the whole point of the split (see the #226 issue body).
##
## Deliberately NOT part of [TooltipFan]: the coordinator only exists at
## runtime (mounted under the HUD), but "drag a panel, watch the line follow"
## has to work with just the fan scene open. Splitting the concern this
## way means panel position is the only authored quantity in EITHER context.
##
## Finds its FanUnits by group (`fan_unit`), never by NodePath — the mount
## contract's "bindings resolve by type/group, not authored NodePaths".
## Every FanUnit instance in the fan scene must carry that group (authored
## in the .tscn's `groups=` on the node, not in code).
##
## Since #314 the clock face is shared out among the PARTICIPATING units only
## (see [member FanUnit.participating]) and each unit's angle is EASED toward
## its slot rather than snapped — so a panel igniting mid-hover makes its
## neighbours slide over instead of teleporting. Standalone in the editor every
## unit participates, so an author still sees the full spread.
##
## Since #307 it derives BOTH trace endpoints. The origin end is the clock
## spread described below; the terminus end is Decision 4's derived anchor plus
## [member FanUnit.anchor_slide]. So a unit's `position` — where its panel
## sits — is the only thing an author places.
##
## SERIALIZATION INVARIANT: this driver may READ a unit's own authored
## properties (`position`, `anchor_slide`, `arrival_axis`, `trunk_length`) but
## must never WRITE them. `godot-workflow.md` forbids a @tool script writing a
## derived value into an `@export`, and the only reason the per-frame
## `from_point` / `to_point` / `trunk_length` writes don't dirty `fan.tscn`
## is that `Trace` is a NON-EDITABLE descendant of an instanced scene, so
## Godot never serializes them. A unit's own properties are direct, editable
## child properties of the fan scene and have no such protection — which is also
## why the route knobs live on the unit and the derived results live on the
## trace, never the reverse.

const _GROUP := &"fan_unit"

@export_group("Clock pins")
## Degrees between adjacent trace origins around the node's rim — one hour on
## an analog clock face. 3 traces sit at 11/12/1, 4 at 10:30/11:30/12:30/1:30,
## always symmetric about 12 o'clock.
@export_range(0.0, 90.0, 0.5) var pin_step_degrees := 30.0
## Ceiling on the fan's total spread. Past this the step compresses rather than
## the arc widening — beyond roughly ±60° a straight-up `trunk_dir` starts
## reading wrong, and squeezing is the better answer than tilting the trunks.
@export_range(0.0, 360.0, 1.0) var max_arc_degrees := 120.0
## Fraction of the node's radius the pins sit at. Below 1 they sit just inside
## the rim, so traces emerge FROM the chip rather than floating off it.
@export_range(0.0, 2.0, 0.01) var pin_factor := 0.8
## Radius used when there is no live node to measure — i.e. the plain editor,
## which has neither a camera nor a hovered [SkillNode]. Keeps trace start→end
## correct with the fan scene open standalone, which is the whole point of
## this script existing separately from [TooltipFan].
@export var preview_pin_radius := 32.0

## How fast a pin slides to a new slot when the participating set changes, as
## the exponential-decay rate in `1 - exp(-rate * delta)`. Frame-rate
## independent, and it eases out for free — no Tween, which keeps this class
## inside the fan's "no clock but your own" contract. ~12 lands the slide in
## roughly a quarter second, matching the panel unfurl it accompanies.
@export_range(1.0, 40.0, 0.5) var pin_slide_rate := 12.0

## Below this many radians from its target a pin just snaps — stops the decay
## from chasing an asymptote forever and re-writing `from_point` every frame
## for a sub-pixel gain.
const _PIN_SETTLE_EPSILON := 0.0005

## The hovered node's radius in SCREEN space, pushed in by [TooltipFan] every
## frame (`node.radius * canvas_transform.get_scale().x`). Zero/unset falls back
## to [member preview_pin_radius].
##
## This is what makes the fan zoom-reactive: pins ride the node's VISIBLE rim at
## every zoom level while the panels stay screen-constant and legible. Trace
## length then changes as a consequence of the origin moving, not as a rule of
## its own.
var node_radius := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_apply(delta)


## Re-derives both endpoints for every unit, with every pin SNAPPED to its slot
## rather than eased into it. Public + idempotent so tests can call it directly
## on a single frame instead of waiting on `_process` — matches the "call the
## continuation directly" testing pattern already used by fan_trace/fan_unit
## tests in this epic.
##
## Snapping is what makes it a usable assertion target: an eased call describes
## a pin somewhere between two slots, which no test can predict. `_process`
## goes through [method _apply] with a real delta instead.
func refresh() -> void:
	_apply(-1.0)


## One pass over the participating units: settle each one's pin angle (eased
## when `delta >= 0`, snapped otherwise), then re-derive its terminus from the
## panel's live rect.
func _apply(delta: float) -> void:
	var units := units_in_fan_order()
	for i in range(units.size()):
		_place_pin(units[i], i, units.size(), delta)
		_reroute(units[i])


## Recomputes and applies one unit's derived terminus.
func reroute(unit: Node) -> void:
	_reroute(unit)


## Parks unit `i` of `n`'s trace origin on the clock face: a uniform step
## between neighbours, symmetric about 12 o'clock, at [member pin_factor] of
## the node's radius. The skill node is the chip and these are its pins.
##
## `n` is the PARTICIPATING count, so the slot a unit gets depends on which of
## its neighbours currently have content. A negative `delta` snaps to the slot;
## otherwise the unit's [member FanUnit.pin_angle] decays toward it, which is
## what turns "Owner just became eligible" into a slide rather than a jump.
##
## RADIUS IS NEVER EASED — only the angle is. The radius tracks the node's
## screen-space rim and therefore the camera zoom; lagging it would make the
## pins visibly trail the node during a zoom, which is a different (and wrong)
## behaviour from easing a slot change.
func _place_pin(unit: Node, i: int, n: int, delta: float) -> void:
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	if trace == null:
		return
	var radius := (node_radius if node_radius > 0.0 else preview_pin_radius) * pin_factor
	var pin := offset_at_angle(_settle_pin_angle(unit, i, n, delta), radius)
	# `pin` is in FAN space; `from_point` is read in the trace's own local
	# space. The unit carries the panel's offset (#307 D), so subtract the whole
	# chain back out — this is what keeps the origin nailed to the node while
	# the unit itself is dragged anywhere.
	var unit_pos: Vector2 = (unit as Node2D).position if unit is Node2D else Vector2.ZERO
	trace.from_point = pin - unit_pos - trace.position


## Pure geometry: where pin `i` of `n` sits, relative to the node's centre.
## Static and dependency-free so the clock is testable without a scene.
##
## `step` is degrees between neighbours (30 = one clock hour). The spread is
## `(n-1) * step`; if that exceeds `max_arc` the step COMPRESSES to fit rather
## than the arc widening past where an upward trunk still reads right.
static func pin_offset(i: int, n: int, radius: float, step: float, max_arc: float) -> Vector2:
	return offset_at_angle(pin_angle(i, n, step, max_arc), radius)


## The ANGLE half of [method pin_offset], split out because #314 eases the
## angle while leaving the radius live (see [method _place_pin]). Radians
## clockwise from 12 o'clock; 0 is straight up.
static func pin_angle(i: int, n: int, step: float, max_arc: float) -> float:
	if n <= 1:
		return 0.0
	var used_step := step
	if max_arc > 0.0 and (n - 1) * step > max_arc:
		used_step = max_arc / float(n - 1)
	# Centre the run on 12 o'clock: index (n-1)/2 lands at exactly 0°.
	return deg_to_rad((i - (n - 1) * 0.5) * used_step)


## The offset half: an angle (radians clockwise from 12) on a circle of
## `radius`. +theta is clockwise (toward 1 o'clock) in Godot's y-down space —
## the convention [method FanAnchorDriver.fan_sort_angle] mirrors.
static func offset_at_angle(theta: float, radius: float) -> Vector2:
	return Vector2(sin(theta), -cos(theta)) * radius


## Moves `unit`'s stored [member FanUnit.pin_angle] toward the slot `i` of `n`
## it should occupy, and returns the value to draw this frame.
##
## `delta < 0` (or a first sighting, where the stored angle is `NAN`) assigns
## the target outright. Otherwise it's exponential decay at [member
## pin_slide_rate] — frame-rate independent, eases out on its own, and owns no
## Tween, so the fan's "each thing animates itself, nobody holds a shared
## clock" contract survives intact.
##
## A non-[FanUnit] member has nowhere to store an angle and is simply never
## eased; it reads its target directly. Nothing in the fan scene is in that
## category today ([method _units] already filters to units carrying a
## `%Trace`/`%Panel` pair), so this is a guard, not a code path.
func _settle_pin_angle(unit: Node, i: int, n: int, delta: float) -> float:
	var target := pin_angle(i, n, pin_step_degrees, max_arc_degrees)
	var fan_unit := unit as FanUnit
	if fan_unit == null:
		return target
	var current: float = fan_unit.pin_angle
	if delta < 0.0 or is_nan(current):
		fan_unit.pin_angle = target
		return target
	if absf(target - current) <= _PIN_SETTLE_EPSILON:
		fan_unit.pin_angle = target
		return target
	var t: float = 1.0 - exp(-pin_slide_rate * delta)
	fan_unit.pin_angle = lerpf(current, target, clampf(t, 0.0, 1.0))
	return fan_unit.pin_angle


func _reroute(unit: Node) -> void:
	if not is_instance_valid(unit):
		return
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	var panel: FanPanel = unit.get_node_or_null("%Panel")
	if trace == null or panel == null:
		return
	var rect := FanAnchor.panel_rect_of(panel)
	var slide: float = unit.anchor_slide if unit is FanUnit else 0.5
	var axis: FanAnchor.Axis = unit.arrival_axis if unit is FanUnit else FanAnchor.Axis.AUTO
	var desired_trunk: float = unit.trunk_length if unit is FanUnit else 0.0
	var route := FanAnchor.solve_route(trace.from_point, rect, trace.route_params(), axis, slide, desired_trunk)
	trace.to_point = route.anchor
	# The solver's answer, not an echo of what's already on the trace — it reads
	# only `trunk`/`trunk_dir` out of route_params() and treats trunk length as an
	# output, so writing it back here can't feed itself. Under AUTO this is just
	# the unit's authored length passed through (0 = keep the bend fraction).
	trace.trunk_length = route.trunk_px


## The PARTICIPATING units in ANGULAR order around the node — the order clock
## pins are handed out in (and, via [TooltipFan], the order the fan staggers
## in).
##
## Deliberately NOT tree order: tree order is authoring order, which says
## nothing about where a panel sits, so handing out clock slots that way would
## start two traces on each other's side of the node and force them to cross.
## Sorting angularly is what guarantees they don't. (Pre-#314 this mattered
## doubly, because the three occupancy variants were inherited scenes and tree
## order pinned each newly-appended unit last regardless of position.)
func units_in_fan_order() -> Array[Node]:
	var out := _units()
	out.sort_custom(func(a: Node, b: Node) -> bool: return fan_sort_angle(a) < fan_sort_angle(b))
	return out


## Sort key for one fan member: the CLOCK ANGLE of its panel centre around the
## node, in the same convention [method pin_offset] uses (radians clockwise from
## 12 o'clock). So the panel sitting at 10 o'clock gets the 10 o'clock pin.
##
## Angle, not x — that distinction is the whole point. Sorting by x hands the
## leftmost pin to whichever panel is furthest LEFT, but a panel can be further
## left while being ANGULARLY nearer to vertical because it also sits much
## higher. Owner (-320,-340) is 43° west of vertical; NodeStats (-195,-150) is
## 52°. NodeStats is the NWW one and must take the outer pin, yet x-order gives
## it to Owner — the two outermost traces start on each other's side and have to
## cross to reach their panels.
##
## Falls back to the member's own position for a panel-less member
## (GrantedModifiersRoot, which duck-types the fan contract without a FanPanel).
## That parks `Roots` at the end of [TooltipFan]'s stagger: it hangs straight
## down at 6 o'clock, so its angle is ±π — outside the arc the others sweep. It
## takes no clock pin either, [method _units] excludes it for having no
## `%Trace`/`%Panel`.
static func fan_sort_angle(member: Node) -> float:
	var centre: Vector2 = (member as Node2D).position if member is Node2D else Vector2.ZERO
	var panel: FanPanel = member.get_node_or_null("%Panel")
	if panel != null:
		centre += FanAnchor.panel_rect_of(panel).get_center()
	# Mirrors pin_offset's Vector2(sin, -cos): 0 = straight up, +ve clockwise.
	return atan2(centre.x, -centre.y)


## Every clock-pin-eligible member: in the group, carrying a `%Trace`/`%Panel`
## pair, and PARTICIPATING in the current hover.
##
## The participation filter (#314) is what makes the spread depend on how many
## panels actually have content: three eligible units get 11/12/1 rather than
## three of the six slots a full fan would use, so an unowned node's fan is
## tight instead of gap-toothed. Every unit defaults to participating, so with
## `fan.tscn` open standalone in the editor this is still "all of them" and an
## author sees the widest spread the fan can produce.
func _units() -> Array[Node]:
	var out: Array[Node] = []
	for n in find_children("*", "", true, false):
		if not n.is_in_group(_GROUP):
			continue
		if n.get_node_or_null("%Trace") == null or n.get_node_or_null("%Panel") == null:
			continue
		if n is FanUnit and not (n as FanUnit).participating:
			continue
		out.append(n)
	return out
