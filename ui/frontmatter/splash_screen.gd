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
## [b]Leg 1[/b] — the charge. Starts on the press, runs for
## [member charge_duration], and zooms out from
## [method FrontmatterLayout.splash_camera] to
## [method FrontmatterLayout.charged_camera] while the [ChargeGlow] on the root
## ramps from [constant Emissive.INERT] toward [constant Emissive.PEAK]. The ring
## stays UNLIT throughout — the thing being sold is the build-up. This is the
## "make room NORTH" beat: the root keeps its horizontal slot and only takes the
## vertical, so the needle has somewhere to land.
##
## [b]The BOOM[/b] — at the seam. The root reads allocated, the charge detonates
## into a shockwave, and the game's own allocation needle drops.
##
## [b]Leg 2[/b] — the existing [method FrontmatterRoot.focus] on the root, which
## from the charged pose is a pure horizontal pan into the hero slot.
##
## [b]What this replaced, and why the old knobs are gone.[/b] The root used to
## snap to its final lit state in one frame, hold there for an `allocation_hold`,
## and then travel with the needle dropping a `spike_lead` fraction INTO the
## travel. Both knobs are retired. `spike_lead` existed only to dodge a clipping
## defect — the needle is `radius * AllocationVFX.SPIKE_HEIGHT_FACTOR` in WORLD
## units, so at [constant FrontmatterLayout.SPLASH_ZOOM] it was 845px tall on a
## 960px screen whose root sat 422px down. The BOOM now happens at
## [constant FrontmatterLayout.TREE_ZOOM] with the root in the hero slot: 264px
## of needle against 480px of headroom. The defect cannot recur, so the knob that
## dodged it has nothing left to do.
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
## `0.0` runs the whole advance in one frame, which is also what
## [member FrontmatterRoot.reduce_motion] collapses it to.
@export_range(0.0, 3.0, 0.05) var charge_duration: float = 0.5

@onready var _prompt: Label = %Prompt

var _frontmatter: FrontmatterRoot = null
## One-way latch. A second press while the camera is still moving must not
## re-trigger the advance — #574 names this explicitly, and without it a held
## key or a double click restarts the motion from wherever it had got to.
var _advanced: bool = false
## Leg 1's tween. Held so the BOOM can kill it — see [method _end_charge].
var _leg_one: Tween = null


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
## the tween to have arrived — see there.
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
	var from := _frontmatter.camera.current_transform()
	var to := FrontmatterLayout.charged_camera(_frontmatter.tree)
	var glow := _charge_glow()
	if glow != null:
		glow.set_progress(0.0)
	_leg_one = create_tween()
	_leg_one.tween_method(_drive_charge.bind(from, to), 0.0, 1.0, _charge_seconds())


## One frame of leg 1. The eased curve lives in [FrontmatterCamera] so the camera
## owns every easing decision in this menu; the glow takes the RAW `t`, because
## its own look is not a camera motion.
func _drive_charge(t: float, from: Transform2D, to: Transform2D) -> void:
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	if _frontmatter.camera != null:
		_frontmatter.camera.apply(from.interpolate_with(to, FrontmatterCamera.ease_charge(t)))
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
	_frontmatter.camera.apply(FrontmatterLayout.charged_camera(_frontmatter.tree))


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
static func is_any_button(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
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
