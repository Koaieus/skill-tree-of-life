@tool
class_name SplashScreen
extends Control

## The attract state — which is not a screen at all, but the frontmatter's own
## camera parked hard on the root node (#574).
##
## [b]"Press any key" IS allocating the first node.[/b] The motion notes are
## explicit: [i]"The splash 'press any button' prompt is really just allocating
## the very first node of the run."[/i] So press any key -> allocate root ->
## allocate Single Player -> allocate New Game must read as the same action four
## times, and the only way that reads true is if the splash and the tree are the
## same picture at two zoom levels. There is no cut and no cross-fade.
##
## [b]Advancing is a CHARGE and a BOOM, across two camera legs (#734).[/b] Owner,
## 2026-09-03: [i]"it should ramp up the ring. a bespoke effect, not part of the
## regular skillnodes. just for this one. the idea is this: click it, and it
## starts glowing, until BOOM allocation vfx (which is some power needle spike
## thingy)."[/i] So:
##
## [b]Leg 1[/b] — the charge, and it is TWO beats rather than one. For the first
## [member charge_camera_fraction] of [member charge_duration] the camera crawls
## out from [method FrontmatterLayout.splash_camera] to
## [method FrontmatterLayout.charged_camera] — "slow slow", zooming a little and
## taking the tiny pan up. Then it STOPS. For the remaining fraction the frame is
## perfectly still while the [ChargeGlow] finishes ramping from
## [constant Emissive.INERT] toward [constant Emissive.PEAK]. The ring stays
## UNLIT throughout — the thing being sold is the build-up, and the stillness is
## what lets it read as a wind-up rather than as more camera motion.
##
## [b]The BOOM[/b] — into that stillness. The root reads allocated, the charge
## detonates into a shockwave, and the game's own allocation needle drops, all in
## one frame with nothing else moving. Owner, 2026-09-03: [i]"crescendo: stop
## zooming/panning (the whole node+spike would still be taking the majority of
## the screen), the vfx + vfx + vfx all hit."[/i]
##
## [b]The settle[/b] — [member settle_pause] of dead air, letting the crescendo
## land before the menu pulls away from it.
##
## [b]Leg 2[/b] — the existing [method FrontmatterRoot.focus] on the root: the
## slide into the hero slot, carrying the LAST of the zoom-out with it. Leg 1
## stops at [member charge_end_zoom], short of tree zoom, so the flash lands
## while the camera is still opening rather than after it has settled.
##
## [b]What this replaced, and why the old knobs are gone.[/b] The root used to
## snap to its final lit state in one frame, hold there for an `allocation_hold`,
## and then travel with the needle dropping a `spike_lead` fraction INTO the
## travel. Both knobs are retired. `spike_lead` existed only to dodge a clipping
## defect — the needle is `radius * AllocationVFX.SPIKE_HEIGHT_FACTOR` in WORLD
## units, so at [constant FrontmatterLayout.SPLASH_ZOOM] it was 845px tall on a
## 960px screen whose root sat 422px down. The BOOM now happens at
## [member charge_end_zoom] with the root pushed south to
## [constant FrontmatterLayout.CHARGE_SLOT_Y_RATIO] — but the containment that
## placement bought is NOT a guard any more. Owner, 2026-09-03: *"looks can
## differ, and it's a matter of taste, having the thing entirely on screen or
## partially off screen, is not something we should be pinning with tests. the
## orchestration as a whole is more important."* The framing follows whatever
## the scene authors; what is pinned (in `test_splash.gd`) is the orchestration.
##
## [b]This scene therefore paints no background.[/b] The tree is meant to be
## visible behind the title, hugely magnified — that is the whole effect.
##
## [b]It parks the camera rather than being asked to.[/b] [FrontmatterRoot.build]
## ends on `focus(root, true)`, so by the time this node is ready the camera is
## already at tree zoom and the root already reads allocated. Undoing both here,
## in `_ready`, keeps the whole splash concern in one file instead of threading a
## start-up mode through the shell — and it is why this node must be ordered
## AFTER the frontmatter in `meta_root.tscn`.
##
## Gamepad is #576, which is sequenced immediately after this unit and owns the
## input side. Keep new input handling there, not here.

## Emitted once, when the attract state gives way to the tree. The shell and
## `test_meta_routing_parity.gd` hang off it.
signal advanced

## The frontmatter this is the attract state OF. Injected as a NodePath by the
## composing scene per `.claude/rules/scene-composition.md`, rather than looked
## up by `get_node` here.
@export var frontmatter_path: NodePath

## Seconds the prompt takes to fade down and back up once.
@export_range(0.0, 4.0, 0.05) var pulse_period: float = 1.0

## Seconds the charge takes — leg 1, from the press to the BOOM (#734).
##
## [b]It is a fixed logical delay, never an await on the charge's own tween.[/b]
## `.claude/rules/presentation-clock.md` is the rule: the reveal is scheduled off
## a clock this file owns, so retuning the [ChargeGlow] cannot silently retune
## the menu, and the glow is handed a `progress` in 0..1 that gates nothing.
##
## It replaces the retired `allocation_hold`, which held an ALREADY LIT root
## doing nothing. Owner, 2026-09-03: [i]"1, could have an easing function thats
## slow at the start for a graceful move"[/i] — see
## [method FrontmatterCamera.ease_charge].
##
## [b]Raised 0.5 -> 2.2 by owner call 2026-09-03.[/b] Verbatim: [i]"the zoomout
## (while glowing up): needs to be slower... we could make the glow up last a bit
## longer too, it's now 1s? could make it 2 or almost 3 even idk."[/i] (It was
## actually 0.5s, not 1s.) The range reaches 3.0 so the upper end of that guess
## is dialable without a code edit.
##
## `0.0` runs the whole advance in one frame, which is also what
## [member FrontmatterRoot.reduce_motion] collapses it to.
@export_range(0.0, 3.0, 0.05) var charge_duration: float = 2.2

## What fraction of the charge the CAMERA moves for. The rest of the charge is
## held perfectly still while the glow finishes winding up (#734).
##
## [b]This is the beat, and nothing else in the file provides it.[/b] Owner,
## 2026-09-03, laying out the structure: [i]"slow slow little bit of zoomout +
## the tiny pan up starts / glow rampup starts / crescendo: stop
## zooming/panning (the whole node+spike would still be taking the majority of
## the screen), the vfx + vfx + vfx all hit."[/i] So the camera must come to
## REST before the BOOM rather than still be moving through it: the frame goes
## quiet, and only then does everything hit at once.
##
## The glow keeps ramping across the WHOLE charge, held tail included — the
## stillness is what makes the crescendo read, so the ring is still building
## while nothing else moves. See [method charge_pose] for the clamp that
## implements it and [method FrontmatterCamera.ease_charge] for why the curve
## has to decelerate into this stop rather than slam into it.
@export_range(0.05, 1.0, 0.05) var charge_camera_fraction: float = 0.6

## Dead air between the BOOM and leg 2 setting off — the owner's [i]"slight
## settlement pause"[/i] (2026-09-03), letting the crescendo land before the
## menu pulls away from it.
##
## [b]A fixed logical delay, never an await on the detonation's tween.[/b] Same
## rule as [member charge_duration] — `.claude/rules/presentation-clock.md` — so
## retuning [ChargeGlow]'s shockwave cannot silently retune the menu.
@export_range(0.0, 2.0, 0.05) var settle_pause: float = 0.4

## How far leg 1 zooms out — an INTERMEDIATE zoom, deliberately short of
## [constant FrontmatterLayout.TREE_ZOOM] (#734).
##
## [b]Leg 1 opens the shot; leg 2 finishes it.[/b] Owner, 2026-09-03: [i]"the
## camera zooms out FAST and A LOT by the time the alloc vfx hits. we could keep
## it closer a bit longer, like Hearthstone's intro... we play our little
## animation while it starts zooming out a little, then more so / faster so when
## the alloc vfx has just started (its a short flash anyway)"[/i]. Ending leg 1
## here rather than at tree zoom leaves the remaining zoom-out to ride leg 2's
## pan, so the needle flashes mid-motion instead of after the camera has parked.
##
## [b]The range admits whatever the scene authors — nothing more deliberate
## than that.[/b] The old 2.4 cap (the `653 / 264` = **2.47** headroom ceiling
## behind it) was the #734 containment guard, retired with the containment
## itself: whether the needle sits wholly on screen or rises past the top is
## taste, not a test — Owner, 2026-09-03: *"the orchestration as a whole is
## more important."* Keep the range admitting the authored value so the
## inspector can always re-dial it honestly.
@export_range(1.0, 3.0, 0.05) var charge_end_zoom: float = 2.2

## The shape of leg 1's zoom-out — 1.0 is linear, higher holds the splash shot
## longer and then opens harder. See [method FrontmatterCamera.ease_charge]; the
## feel is the owner's to dial and nothing asserts the curve.
@export_range(1.0, 6.0, 0.1) var charge_ease_power: float = 3.5

@onready var _prompt: Label = %Prompt

var _frontmatter: FrontmatterRoot = null
## One-way latch. A second press while the camera is still moving must not
## re-trigger the advance — #574 names this explicitly, and without it a held
## key or a double click restarts the motion from wherever it had got to.
var _advanced: bool = false
## Leg 1's tween. Held so the BOOM can kill it — see [method _end_charge].
var _leg_one: Tween = null
## Leg 1's endpoints, snapshotted at the press. Read by [method charge_pose].
var _charge_from: Transform2D = Transform2D.IDENTITY
var _charge_to: Transform2D = Transform2D.IDENTITY


## [b]Deliberately NOT guarded by `Engine.is_editor_hint()`.[/b] Nothing below is
## OS-facing — a node lookup, a camera write and a tween — and #578's live tab
## mounts this scene with the hint true, where a blanket early return would leave
## the splash silently inert and untestable from GUT (hint false). See
## `.claude/rules/gdscript-pitfalls.md`. `_park` null-guards instead, which also
## covers opening `splash_screen.tscn` on its own with no frontmatter to point at.
func _ready() -> void:
	_frontmatter = get_node_or_null(frontmatter_path) as FrontmatterRoot
	_park()
	_pulse()


## Zooms the camera onto the root and takes back the allocation `build()` just
## granted it. The root is what the player is about to allocate; it must not
## already read as allocated while the prompt is still asking.
func _park() -> void:
	if _frontmatter == null or _frontmatter.tree == null:
		return
	if _frontmatter.camera != null:
		_frontmatter.camera.apply(FrontmatterLayout.splash_camera(_frontmatter.tree))
	var root_view := _frontmatter.view_for(_frontmatter.tree.root)
	if root_view != null:
		root_view.allocated = false


func _pulse() -> void:
	if pulse_period <= 0.0:
		return
	var blink := create_tween().set_loops()
	blink.tween_property(_prompt, "modulate:a", 0.3, pulse_period)
	blink.tween_property(_prompt, "modulate:a", 1.0, pulse_period)


## Allocate the root: charge up, BOOM, then pan out to the tree. Idempotent by
## the latch — later calls do nothing at all.
##
## [b]The charge and the BOOM run on two clocks, and only the timer is
## authoritative.[/b] The tween below is presentation and gates nothing; the
## [SceneTreeTimer] is what decides when the BOOM happens
## (`.claude/rules/presentation-clock.md`). They complete on different frames, so
## [method _end_charge] writes the charged pose explicitly rather than trusting
## the tween to have arrived — see there. Since the camera finishes its motion at
## [member charge_camera_fraction] and merely holds after that, a late tween
## frame is now harmless anyway; the explicit write remains the guarantee.
##
## Public because it is the whole behaviour of this node, and a test that has to
## synthesize an [InputEventKey] to reach it would be testing Godot's input
## routing rather than this decision. The input handlers below are thin wrappers.
func advance() -> void:
	if _advanced:
		return
	_advanced = true
	visible = false
	_lock_navigation()
	if _charge_seconds() <= 0.0:
		_boom()
	else:
		_start_charge()
		get_tree().create_timer(_charge_seconds()).timeout.connect(_boom)
	advanced.emit()


## Closes the menu's navigation gate for the length of the charge.
##
## [b]The lock is the price of leg 1 being a live camera writer.[/b] The old hold
## was a passive timer that wrote nothing, so a player mashing through it was
## harmless. Leg 1 drives the [Camera2D] every frame for [member charge_duration];
## a player who navigates during it starts [FrontmatterRoot]'s own `_transition`
## onto the same camera and the two fight. Owner call 2026-09-03: [i]lock input
## for the charge.[/i] You cannot steer during the charge; navigation resumes at
## the BOOM. One writer at all times, no abort path, and a charge that always
## completes — so the [ChargeGlow] is never left stranded mid-ramp.
##
## [b]It gates in [FrontmatterRoot], not in this file's `_unhandled_input`.[/b]
## Consuming events here would look like it kept the splash concern in one place,
## but [MenuNodePickRegion] is a [Control] and GUI picking runs before
## `_unhandled_input` — so a CLICK would reach `FrontmatterRoot._on_view_activated`
## and `focus()` having never passed this node. [method FrontmatterRoot.focus] is
## the one seam both the keyboard and the mouse path converge on.
func _lock_navigation() -> void:
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	_frontmatter.navigation_locked = true


## Leg 1: the splash's own camera tween, from wherever the camera is now to the
## charged pose, with the charge ring ramping on the same clock.
##
## [b]It does NOT go through [method FrontmatterRoot.focus].[/b] That would fire
## `_sync_allocation` — lighting the ring on the press, which is the whole defect
## — and travel to the HERO pose, which is the leg-2 half being split off.
## `camera.set_progress` is driven only by the `_transition` tween `focus()`
## creates, so while the menu is idle nothing else writes the camera and this may
## drive [method FrontmatterCamera.apply] directly. It is the same access
## [method _park] already takes.
func _start_charge() -> void:
	if _frontmatter == null or _frontmatter.tree == null or _frontmatter.camera == null:
		return
	_charge_from = _frontmatter.camera.current_transform()
	_charge_to = FrontmatterLayout.charged_camera(_frontmatter.tree, charge_end_zoom)
	var glow := _charge_glow()
	if glow != null:
		glow.set_progress(0.0)
	_leg_one = create_tween()
	_leg_one.tween_method(_drive_charge, 0.0, 1.0, _charge_seconds())


## Leg 1's camera pose at clock position `t` (0..1) — the PURE half of the
## charge, and the same function the tween drives.
##
## [b]It exists so a test never has to sample a tween mid-flight.[/b] That is the
## convention [FrontmatterCamera] already states for
## [method FrontmatterCamera.transform_at]: assert `t == 0` and `t == 1` rather
## than chasing intermediate frames. It is not fussiness — a [Tween] stops
## advancing while the [SceneTree] is paused whereas a [SceneTreeTimer] goes on
## firing, so a test that reads the live camera a fixed wall-clock delay into
## leg 1 is asserting the harness's frame delivery, not this file's decision.
func charge_pose(t: float) -> Transform2D:
	# The camera's own clock, which runs out BEFORE the charge does: past
	# `charge_camera_fraction` this pins at 1.0, so the pose stops changing and
	# the frame is still for the rest of the ramp. Clamping here rather than in
	# the tween keeps this the one place the split is expressed, and keeps it a
	# pure function a test can sample at any `t`.
	var window := clampf(charge_camera_fraction, 0.01, 1.0)
	var camera_t := clampf(clampf(t, 0.0, 1.0) / window, 0.0, 1.0)
	return _charge_from.interpolate_with(
		_charge_to, FrontmatterCamera.ease_charge(camera_t, charge_ease_power)
	)


## One frame of leg 1. The eased curve lives in [FrontmatterCamera] so the camera
## owns every easing decision in this menu; the glow takes the RAW `t`, because
## its own look is not a camera motion.
func _drive_charge(t: float) -> void:
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	if _frontmatter.camera != null:
		_frontmatter.camera.apply(charge_pose(t))
	var glow := _charge_glow()
	if glow != null:
		glow.set_progress(t)


## BOOM — the seam between the two legs, and the one moment this whole node
## exists to sell.
##
## [b]Order is load-bearing, three times over.[/b]
##
## 1. [method _end_charge] first, so leg 2 departs from a pose this file WROTE
##    rather than from wherever the tween happened to have got to.
## 2. The `allocated` write lands BEFORE the focus guard below. A player who got
##    ahead trips that guard; writing after it would leave the root never
##    allocated by the splash at all, and let their own `focus()` fire an
##    unscheduled spike at an arbitrary zoom. Before it, the mash path stays
##    exactly what it was. The write is also what makes `_sync_allocation` see no
##    false->true transition when leg 2 focuses, so it fires no SECOND spike —
##    the same trick the old code played on the press, relocated to here.
## 3. The lock is released before the guard AND before leg 2, because leg 2 goes
##    through the very gate the lock closes.
func _boom() -> void:
	_end_charge()
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	if _frontmatter.tree == null:
		return
	var root_view := _frontmatter.view_for(_frontmatter.tree.root)
	if root_view != null:
		root_view.allocated = true
	_detonate(root_view)
	_frontmatter.navigation_locked = false
	if _settle_seconds() <= 0.0:
		_depart()
		return
	get_tree().create_timer(_settle_seconds()).timeout.connect(_depart)


## Leg 2: the pan into the hero slot, once the crescendo has been allowed to
## land. Re-checks everything, because a timer fires a frame or more later and
## the world may have moved on.
##
## [b]The focus guard is reachable again, and that is correct.[/b] The lock came
## off at the BOOM, so a player may steer during [member settle_pause] — and if
## they did, this must not yank them home a beat later. That is the same
## protection the guard has always provided, restored to a window where a player
## can actually reach it.
func _depart() -> void:
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	if _frontmatter.tree == null:
		return
	if _frontmatter.focus_id != _frontmatter.tree.root:
		return
	_frontmatter.focus(_frontmatter.tree.root)


## Ends leg 1 and puts the camera exactly where leg 1 was going.
##
## [b]The explicit write is not belt-and-braces, it is the fix for a real
## desync.[/b] The charge runs on two clocks — a [Tween] for the camera and a
## [SceneTreeTimer] for this BOOM — and they complete on different frames. If the
## timer wins, leg 1 is still a few pixels short; [method FrontmatterCamera.travel_to]
## then snapshots [method FrontmatterCamera.current_transform] as leg 2's origin
## and the pan starts from the wrong place. It would read as an intermittent jump
## at the exact instant the player is looking, and would not reproduce on demand.
## Writing the charged pose here makes leg 2's origin independent of frame
## ordering, which is why a test can assert it.
func _end_charge() -> void:
	if _leg_one != null and _leg_one.is_valid():
		_leg_one.kill()
	_leg_one = null
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	if _frontmatter.tree == null or _frontmatter.camera == null:
		return
	_frontmatter.camera.apply(
		FrontmatterLayout.charged_camera(_frontmatter.tree, charge_end_zoom)
	)


## The detonation: the bespoke shockwave, then the game's OWN allocation needle.
##
## [b]The needle stays reused, the shockwave does not get to be.[/b]
## [method AllocationVFX.spawn_alloc_spike] is the same "skill point from the
## heavens" every real allocation drops and must remain so — that is the conceit.
## The shockwave is bespoke to this one beat and has no second caller, so it
## lives on the [ChargeGlow] rather than being added to [AllocationVFX].
##
## [method ChargeGlow.detonate] is also what TAKES THE CHARGE AWAY. Without it
## the ring would sit at [constant Emissive.PEAK] forever behind the root's
## ordinary lit state — brighter than anything else on the screen, permanently,
## which is a worse artifact than the instant-lit snap this replaced.
func _detonate(root_view: MenuNodeView) -> void:
	var glow := _charge_glow()
	if glow != null:
		glow.detonate(_charge_seconds() <= 0.0)
	if root_view != null:
		root_view.play_allocation_spike()


## The root's charge ring, or null when the frontmatter is not built.
##
## Typed through [SplashRootView] rather than found by name or by scanning
## children: the root's view is an inherited scene with its own script precisely
## so this lookup can be a property read (`.claude/rules/scene-composition.md`).
func _charge_glow() -> ChargeGlow:
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return null
	if _frontmatter.tree == null:
		return null
	var view := _frontmatter.view_for(_frontmatter.tree.root) as SplashRootView
	if view == null:
		return null
	return view.charge


## How long the charge runs. Collapsed to nothing by the accessibility setting,
## exactly as [member FrontmatterRoot.travel_duration] is — a player who asked
## for no motion is not asking for a pause where the motion used to be, and BOTH
## legs have to collapse or the splash would trade a travel for a stare.
func _charge_seconds() -> float:
	if _frontmatter != null and _frontmatter.reduce_motion:
		return 0.0
	return charge_duration


## How long to sit on the crescendo before leg 2 departs. Collapsed by the
## accessibility setting exactly as the charge is — a player who asked for no
## motion is not asking for dead air where the motion used to be, and the suite
## depends on it: `before_each` sets `reduce_motion`, which is the only reason
## these tests see an immediate advance at all.
func _settle_seconds() -> float:
	if _frontmatter != null and _frontmatter.reduce_motion:
		return 0.0
	return settle_pause


## Whether the attract state has already given way. `false` on a fresh menu.
func is_advanced() -> bool:
	return _advanced


## "PRESS ANY BUTTON" has to mean it (#576). Key, gamepad button and mouse all
## advance; before this, a controller player was stuck on the title screen
## looking at a prompt that named the one device it did not accept.
##
## Deliberately NOT an `ui_accept` check: the prompt says ANY button, so this
## takes the raw event kind rather than an action, and a player mashing whatever
## is under their thumb gets through.
## [b]Except the dev reload key.[/b] This node sees `_unhandled_input` BEFORE
## [FrontmatterInput] (it is ordered after the frontmatter in `meta_root.tscn`),
## so without this exclusion F5 would read as "any button", advance the splash,
## and be consumed before the thing that reloads ever saw it — the affordance
## would appear to do nothing except skip the beat it exists to replay.
static func is_any_button(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if FrontmatterInput.is_reload(event):
		return false
	return event is InputEventKey or event is InputEventJoypadButton


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if is_any_button(event):
		advance()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed:
		advance()
		accept_event()
