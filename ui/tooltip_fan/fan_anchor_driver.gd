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
## spread described below; the terminus end is Decision 4's derived anchor —
## edge AND slide, the point on the edge nearest the trunk top. So a unit's
## `position` — where its panel RESTS; [FanLayout] solves where it sits — is
## the only thing an author places.
##
## SERIALIZATION INVARIANT: this driver may READ a unit's own authored
## properties (`position`) but must never WRITE them. `godot-workflow.md`
## forbids a @tool script writing a derived value into an `@export`, and the
## only reason the per-frame `from_point` / `to_point` / `trunk_length` writes
## don't dirty `fan.tscn` is that `Trace` is a NON-EDITABLE descendant of an
## instanced scene, so Godot never serializes them. A unit's own properties are
## direct, editable child properties of the fan scene and have no such
## protection — which is also why the derived results live on the trace and
## the solved layout on `%Panel` (the same cover), never on the unit.

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

@export_group("Trunk")
## How far every trace runs along its trunk before breaking to 45°, in pixels —
## ONE length for the whole fan, so the wires leave the node as an equal-length
## bundle. The trunk top (`pin + trunk_dir * trunk_length`, see
## [method trunk_top_of]) is the point the derived slide aims at and where a
## blooming panel starts.
@export_range(1.0, 300.0, 1.0, "or_greater") var trunk_length := 40.0
## The 45° shoulder every trace breaks out with past its trunk top, in
## pixels — fan-wide like [member trunk_length]. `0` defers to [TraceRouter]'s
## default (the trunk length).
@export_range(0.0, 300.0, 1.0, "or_greater") var shoulder := 0.0

@export_group("Layout")
## [FanLayout]'s spring time constant: how long a panel takes to settle onto
## its rest (or its contact equilibrium) after a disturbance.
@export_range(0.01, 1.0, 0.01, "or_greater") var settle_seconds := FanLayout.DEFAULT_SETTLE_SECONDS
## The gap the solver keeps between any two panels, and between a panel and
## an obstacle, in screen pixels.
@export_range(0.0, 64.0, 0.5, "or_greater") var padding := FanLayout.DEFAULT_PADDING
## Projection passes per step. More holds a crowded fan tighter per frame.
@export_range(1, 16, 1) var relax_iterations := FanLayout.DEFAULT_RELAX_ITERATIONS
## Where panels may sit, in fan space. Defaults to effectively unbounded; the
## window-aware owner of the fan feeds the real one.
@export var keep_in := Rect2(-100000.0, -100000.0, 200000.0, 200000.0)

## The node's own footprint — the chip plus the HealthBar / CoreHealthBar
## above it (`skill_node.tscn`, y −59..−28) — in NODE-LOCAL units, centred on
## the node. Scaled by [member zoom_scale] into the node obstacle.
const NODE_FOOTPRINT := Rect2(-45.0, -70.0, 90.0, 102.0)

## A bloom leg's spring time constant is its trace's `draw_in_duration`
## divided by this. The critically damped spring has ~4% of the way left at
## five time constants, so the panel lands as the trace tip arrives and
## unfurls in place — at the solver's `settle_seconds` it would still be a
## third of the way out when it appears (measured: Addons ~225 px short).
const BLOOM_TIME_CONSTANTS_PER_DRAW := 5.0

## Below this many radians from its target a pin just snaps — stops the decay
## from chasing an asymptote forever and re-writing `from_point` every frame
## for a sub-pixel gain.
const _PIN_SETTLE_EPSILON := 0.0005


## Dev tooling (#309): from the fan scene open in the 2D editor, jump back to
## the sandbox host's "Tooltip Fan" tab. The tab's panel carries the outbound
## half ("✎ Open fan.tscn"). Editor-only — a no-op at runtime.
##
## [b]`EditorInterface` is reached through [method Engine.get_singleton], never
## named directly.[/b] It is an editor-only global, so naming it in a script
## that ships is a PARSE error under an export template — which kills the
## WHOLE script, not just this editor-only function. This file shipped with a
## dead `FanAnchorDriver` for exactly that reason; `Engine.is_editor_hint()`
## does not help, because the failure is at parse time, before any guard runs.
@export_tool_button("◈  Open in Sandbox") var _open_sandbox: Callable = _jump_to_sandbox

func _jump_to_sandbox() -> void:
	if not Engine.is_editor_hint():
		return
	var editor := Engine.get_singleton(&"EditorInterface")
	editor.set_main_screen_editor("Sandbox")
	var host: Node = editor.get_editor_main_screen().get_node_or_null("Sandbox")
	if host != null and host.has_method(&"reveal_tab"):
		host.reveal_tab(&"tooltip_fan")

## The hovered node's radius in SCREEN space, pushed in by [TooltipFan] every
## frame (`node.radius * canvas_transform.get_scale().x`). Zero/unset falls back
## to [member preview_pin_radius].
##
## This is what makes the fan zoom-reactive: pins ride the node's VISIBLE rim at
## every zoom level while the panels stay screen-constant and legible. Trace
## length then changes as a consequence of the origin moving, not as a rule of
## its own.
var node_radius := 0.0

## The canvas zoom the hovered node is drawn at, pushed in next to
## [member node_radius] by [TooltipFan]. Scales [constant NODE_FOOTPRINT] into
## the node obstacle — the node grows with zoom while panels stay
## screen-constant. Zero/unset (the plain editor) reads as 1.
var zoom_scale := 0.0

## One [FanLayout.Body] per PARTICIPATING unit, keyed by instance id; the
## solver's state. Rebuilt (kept, added, dropped) whenever the participating
## set changes.
var _bodies := {}
## Each unit's AUTHORED `%Panel.position` (unit-local), captured the first
## time the driver sees the unit — before any solved write lands on it.
var _panel_base := {}
## The bloom leg per blooming unit, keyed like [member _bodies]: a body with
## no neighbours and no obstacles, springing from the trunk top onto its
## unit's SOLVED position — repulsion off — and dropped on arrival. While one
## exists it, not the solver's body, is what the panel shows.
var _legs := {}
## The last [enum FanUnit.State] seen per unit, for the HIDDEN → IN edge the
## bloom keys on.
var _seen_state := {}


func _ready() -> void:
	set_process(true)
	for n in find_children("*", "FanUnit", true, false):
		var unit := n as FanUnit
		_seen_state[unit.get_instance_id()] = unit.state
		if not unit.state_changed.is_connected(_on_unit_state_changed):
			unit.state_changed.connect(_on_unit_state_changed.bind(unit))


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
##
## It also runs [method FanLayout.settle] to convergence, so a test reads the
## layout the eye sees once the fan has come to rest.
func refresh() -> void:
	_apply(-1.0)


## One pass over the participating units: lay the panels out (one solver step
## when `delta >= 0`, settled otherwise), settle each one's pin angle (eased /
## snapped the same way), then re-derive its terminus from the panel's live
## rect — so pins and routes see the solved position with no change of their
## own.
func _apply(delta: float) -> void:
	_layout(delta)
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
	# The fan-wide trunk goes onto the trace FIRST, so the solver — which reads
	# `trunk_px` out of `route_params()` to ask TraceRouter for the real route —
	# sees the same line the screen draws. It is this driver's export, never a
	# solver output, so writing it every frame cannot feed itself.
	trace.trunk_length = trunk_length
	trace.shoulder = shoulder
	var route := FanAnchor.solve_route(trace.from_point, rect, trace.route_params())
	trace.to_point = route.anchor


# --- Panel layout ([FanLayout]) -------------------------------------------------

## The solver body for `unit`, or null when it is not participating.
## Top-left of its panel rect, in fan space — the SOLVED spot, which the panel
## shows except while it is on its bloom leg.
func body_of(unit: Node) -> FanLayout.Body:
	return _bodies.get(unit.get_instance_id()) if is_instance_valid(unit) else null


## The fixed rects panels keep clear of, in fan space: the node footprint
## scaled by [member zoom_scale], merged with the Roots' live `%Rows` rect
## (unscaled). ONE merged rect — the two sit ~11 px apart, and a panel caught
## in that slot would be handed back and forth between them every pass.
func obstacles() -> Array[Rect2]:
	var s := zoom_scale if zoom_scale > 0.0 else 1.0
	var node_rect := Rect2(NODE_FOOTPRINT.position * s, NODE_FOOTPRINT.size * s)
	var roots := find_child("Roots", false, false) as GrantedModifiersRoot
	var rows: Control = roots.get_node_or_null("%Rows") if roots != null else null
	if rows != null and rows.get_global_rect().has_area():
		node_rect = node_rect.merge(get_global_transform().affine_inverse() * rows.get_global_rect())
	return [node_rect]


## Syncs the bodies to the participating set and to each panel's live size and
## authored rest, advances the solver (one frame, or to convergence for a
## negative `delta`), and writes each solved position onto the unit's
## `%Panel` — never onto the unit, whose `position` is the authored rest.
func _layout(delta: float) -> void:
	var bodies := _sync_bodies()
	if bodies.is_empty():
		return
	var params := {
		"settle_seconds": settle_seconds,
		"padding": padding,
		"relax_iterations": relax_iterations,
	}
	if delta < 0.0:
		FanLayout.settle(bodies, obstacles(), keep_in, params)
		_legs.clear()
	elif delta > 0.0:
		FanLayout.step(bodies, obstacles(), keep_in, params, delta)
		_fly_legs(params, delta)
	for unit in _units():
		_write_panel(unit, _shown_body(unit.get_instance_id()))


## Advances every bloom leg one frame toward its body's CURRENT solved
## position — the same critically damped spring, run by [FanLayout] itself
## with nothing to collide with, timed to its trace's draw-in (see
## [constant BLOOM_TIME_CONSTANTS_PER_DRAW]) — and retires the legs that have
## landed (FanLayout snaps a body within a pixel of its rest onto it, at rest).
func _fly_legs(params: Dictionary, delta: float) -> void:
	for id in _legs.keys():
		var leg: FanLayout.Body = _legs[id]
		var body: FanLayout.Body = _bodies[id]
		leg.size = body.size
		leg.rest = body.position
		var one: Array[FanLayout.Body] = [leg]
		var leg_params := params.duplicate()
		leg_params["settle_seconds"] = _leg_seconds(instance_from_id(id))
		FanLayout.step(one, [], keep_in, leg_params, delta)
		if leg.position == leg.rest and leg.velocity == Vector2.ZERO:
			_legs.erase(id)


func _leg_seconds(unit: Object) -> float:
	var trace: FanTrace = (unit as Node).get_node_or_null("%Trace") if unit is Node else null
	var draw := trace.draw_in_duration if trace != null else settle_seconds
	return draw / BLOOM_TIME_CONSTANTS_PER_DRAW


## What the panel shows: the bloom leg while one is in flight, else the body.
func _shown_body(id: int) -> FanLayout.Body:
	return _legs.get(id, _bodies[id])


func _sync_bodies() -> Array[FanLayout.Body]:
	var out: Array[FanLayout.Body] = []
	var live := {}
	for unit in _units():
		var id := unit.get_instance_id()
		live[id] = true
		var panel: FanPanel = unit.get_node("%Panel")
		if not _panel_base.has(id):
			_panel_base[id] = panel.position
		var body: FanLayout.Body = _bodies.get(id)
		var rect := _panel_rect_in_fan(unit, panel)
		if body == null:
			body = FanLayout.Body.new()
			body.position = rect.position
			_bodies[id] = body
		body.size = rect.size
		body.rest = _rest_of(unit, panel)
		out.append(body)
	for id in _bodies.keys():
		if not live.has(id):
			_bodies.erase(id)
			_legs.erase(id)
	return out


## The panel's authored rect origin in fan space: the unit's `position` plus
## the panel's authored offset inside the unit plus the skin chain.
func _rest_of(unit: Node, panel: FanPanel) -> Vector2:
	return _unit_pos(unit) + _panel_base[unit.get_instance_id()] + _skin_offset(panel)


func _write_panel(unit: Node, body: FanLayout.Body) -> void:
	var panel: FanPanel = unit.get_node("%Panel")
	panel.position = body.position - _unit_pos(unit) - _skin_offset(panel)


func _panel_rect_in_fan(unit: Node, panel: FanPanel) -> Rect2:
	var rect := FanAnchor.panel_rect_of(panel)
	rect.position += _unit_pos(unit)
	return rect


## What [method FanAnchor.panel_rect_of] adds on top of `panel.position`.
static func _skin_offset(panel: FanPanel) -> Vector2:
	return FanAnchor.panel_rect_of(panel).position - panel.position


static func _unit_pos(unit: Node) -> Vector2:
	return (unit as Node2D).position if unit is Node2D else Vector2.ZERO


## Bloom is a VISUAL leg, not a solver state: on a unit's HIDDEN → IN edge its
## panel starts centred on the trunk top and flies onto the position the
## solver already holds for it (bodies are solved warm whether or not the
## panel shows), so the landed layout is exactly the one [method refresh]
## converges to — never a history-dependent equilibrium of its own. The leg
## runs while the trace draws in and the panel is still at `progress 0`.
func _on_unit_state_changed(new_state: FanUnit.State, unit: FanUnit) -> void:
	var id := unit.get_instance_id()
	var was: FanUnit.State = _seen_state.get(id, FanUnit.State.HIDDEN)
	_seen_state[id] = new_state
	if new_state != FanUnit.State.IN or was != FanUnit.State.HIDDEN:
		return
	_sync_bodies()
	_start_leg(unit)


## Re-runs the bloom leg for every participating unit: each panel jumps back
## to its trunk top and flies onto its solved spot again. The bodies are left
## alone — this replays the VISUAL leg, not the solve. A bench control.
func replay_bloom() -> void:
	_sync_bodies()
	for unit in _units():
		if unit is FanUnit:
			_start_leg(unit)


func _start_leg(unit: FanUnit) -> void:
	var id := unit.get_instance_id()
	var body: FanLayout.Body = _bodies.get(id)
	if body == null:
		return
	if is_nan(unit.pin_angle):
		var units := units_in_fan_order()
		_place_pin(unit, units.find(unit), units.size(), -1.0)
	var leg := FanLayout.Body.new()
	leg.size = body.size
	leg.rest = body.position
	leg.position = trunk_top_in_fan(unit) - body.size * 0.5
	_legs[id] = leg
	_write_panel(unit, leg)


## The sort key for `member` in THIS fan: its body's centre angle while it has
## one — the SOLVED spot, so a panel on its bloom leg keeps the pin (and the
## stagger slot) it is flying to — else [method fan_sort_angle].
func order_angle(unit: Node) -> float:
	var body := body_of(unit)
	if body == null:
		return fan_sort_angle(unit)
	var centre := body.position + body.size * 0.5
	return atan2(centre.x, -centre.y)


## [method trunk_top_of] moved out of the trace's local space into fan space.
func trunk_top_in_fan(unit: Node) -> Vector2:
	var trace: FanTrace = unit.get_node_or_null("%Trace") if is_instance_valid(unit) else null
	if trace == null:
		return Vector2.ZERO
	return trunk_top_of(unit) + trace.position + _unit_pos(unit)


## The shared point every wire in the fan diverges from: `unit`'s clock pin plus
## `trunk_length` along its trace's `trunk_dir`. A driver fact (the pin is
## derived here, the length is this export) — the derived slide aims at it and
## a blooming panel starts there. Returns `Vector2.ZERO` for a unit with no
## trace; a zero `trunk_dir` falls back to an upward trunk.
func trunk_top_of(unit: Node) -> Vector2:
	var trace: FanTrace = unit.get_node_or_null("%Trace") if is_instance_valid(unit) else null
	if trace == null:
		return Vector2.ZERO
	var dir: Vector2 = trace.trunk_dir
	if dir == Vector2.ZERO:
		dir = Vector2(0.0, -1.0)
	return trace.from_point + dir.normalized() * trunk_length


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
	out.sort_custom(func(a: Node, b: Node) -> bool: return order_angle(a) < order_angle(b))
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
