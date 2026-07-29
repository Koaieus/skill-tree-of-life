@tool
class_name FanAnchorDriver
extends Node2D

## Tooltip V2 (#226) — keeps every [FanUnit]'s trace terminus derived live
## from its panel's CURRENT position (Decision 4). Attached as the root
## script of every variant scene (`unowned.tscn` / `owned.tscn` /
## `owned_core.tscn`) so a human dragging a panel in the editor sees the
## trace re-route immediately, without opening [TooltipFan] at all — that is
## the whole point of the split (see the #226 issue body).
##
## Deliberately NOT part of [TooltipFan]: the coordinator only exists at
## runtime (mounted under the HUD), but "drag a panel, watch the line follow"
## has to work with just the variant scene open. Splitting the concern this
## way means panel position is the only authored quantity in EITHER context.
##
## Finds its FanUnits by group (`fan_unit`), never by NodePath — the mount
## contract's "bindings resolve by type/group, not per-variant NodePaths".
## Every FanUnit instance in a variant scene must carry that group (authored
## in the .tscn's `groups=` on the node, not in code).
##
## Since #307 it derives BOTH trace endpoints. The origin end is the clock
## spread described below; the terminus end is Decision 4's derived anchor plus
## [member FanUnit.anchor_slide]. So a unit's `position` — where its panel
## sits — is the only thing an author places.
##
## SERIALIZATION INVARIANT: this driver may READ `unit.position` but must never
## WRITE it. `godot-workflow.md` forbids a @tool script writing a derived value
## into an `@export`, and the only reason the existing per-frame `to_point`
## write doesn't dirty the variant scenes is that `Trace` is a NON-EDITABLE
## descendant of an instanced scene, so Godot never serializes it. A unit's
## `position` is a direct, editable child property of the variant and has no
## such protection.

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
## correct with the variant scene open standalone, which is the whole point of
## this script existing separately from [TooltipFan].
@export var preview_pin_radius := 32.0

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


func _process(_delta: float) -> void:
	refresh()


## Re-derives both endpoints for every unit. Public + idempotent so tests can
## call it directly on a single frame instead of waiting on `_process` —
## matches the "call the continuation directly" testing pattern already used by
## fan_trace/fan_unit tests in this epic.
func refresh() -> void:
	var units := units_in_fan_order()
	for i in range(units.size()):
		_place_pin(units[i], i, units.size())
		_reroute(units[i])


## Recomputes and applies one unit's derived terminus.
func reroute(unit: Node) -> void:
	_reroute(unit)


## Parks unit `i` of `n`'s trace origin on the clock face: a uniform step
## between neighbours, symmetric about 12 o'clock, at [member pin_factor] of
## the node's radius. The skill node is the chip and these are its pins.
func _place_pin(unit: Node, i: int, n: int) -> void:
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	if trace == null:
		return
	var radius := (node_radius if node_radius > 0.0 else preview_pin_radius) * pin_factor
	var pin := pin_offset(i, n, radius, pin_step_degrees, max_arc_degrees)
	# `pin` is in VARIANT space; `from_point` is read in the trace's own local
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
	if n <= 1:
		return Vector2(0.0, -radius)
	var used_step := step
	if max_arc > 0.0 and (n - 1) * step > max_arc:
		used_step = max_arc / float(n - 1)
	# Centre the run on 12 o'clock: index (n-1)/2 lands at exactly 0°.
	var theta := deg_to_rad((i - (n - 1) * 0.5) * used_step)
	# +theta is clockwise (toward 1 o'clock) in Godot's y-down space.
	return Vector2(sin(theta), -cos(theta)) * radius


func _reroute(unit: Node) -> void:
	if not is_instance_valid(unit):
		return
	var trace: FanTrace = unit.get_node_or_null("%Trace")
	var panel: FanPanel = unit.get_node_or_null("%Panel")
	if trace == null or panel == null:
		return
	var rect := FanAnchor.panel_rect_of(panel)
	var slide: float = unit.anchor_slide if unit is FanUnit else 0.5
	trace.to_point = FanAnchor.derive_anchor(trace.from_point, rect, trace.trunk_dir, trace.bend_start, slide)


## The units in ANGULAR order around the node — the order clock pins are handed
## out in (and, via [TooltipFan], the order the fan staggers in).
##
## Deliberately NOT tree order. The variants are inherited scenes — `owned`
## appends Owner to `unowned`, `owned_core` appends Core to `owned` — so tree
## order permanently puts the newest unit last no matter where its panel
## actually sits. Handing out clock slots in that order would GUARANTEE crossed
## traces in `owned_core`.
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


func _units() -> Array[Node]:
	var out: Array[Node] = []
	for n in find_children("*", "", true, false):
		if n.is_in_group(_GROUP) and n.get_node_or_null("%Trace") != null and n.get_node_or_null("%Panel") != null:
			out.append(n)
	return out
