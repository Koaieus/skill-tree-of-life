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
## same picture at two zoom levels. There is no cut and no cross-fade: advancing
## is [method FrontmatterRoot.focus] on the root, travelling out from
## [method FrontmatterLayout.splash_camera] to [method FrontmatterLayout.camera_for].
##
## [b]Advancing is three beats, not one.[/b] The root lights up on the press,
## holds there for [member allocation_hold], and the camera then sets off — with
## the allocation needle dropping [member spike_lead] INTO that travel rather
## than before it. The allocation used to be a side effect of the travel, so the
## one moment the splash exists to sell went past in the same frame it happened;
## the correction overshot the other way and fired a 845px needle at a node
## parked 422px down a 960px screen, which is the clipping [member spike_lead]
## exists to answer.
##
## [b]This scene therefore paints no background.[/b] The tree is meant to be
## visible behind the title, hugely magnified — that is the whole effect. The
## code-composed opaque `ColorRect` this replaces existed because the splash used
## to be a curtain in front of a menu that had not been built yet.
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

## Seconds the allocated root is held on screen, hugely magnified, before the
## camera sets off for the tree — the beat between [i]"you allocated it"[/i] and
## [i]"here is what it opens"[/i].
##
## [b]It is a fixed logical delay, never an await on the spike's tween.[/b]
## `.claude/rules/presentation-clock.md` is the rule: a reveal is scheduled off
## a clock the code owns, so retuning the VFX cannot silently retune the menu.
## What it holds is the LIT root, not the needle — the needle now drops into the
## travel this delays (see [member spike_lead]), so this is the anticipation beat
## between "you pressed it" and "it opens", and the beat a charge-up windup
## would eventually fill.
##
## `0.0` runs the whole advance in one frame, which is also what
## [member FrontmatterRoot.reduce_motion] collapses it to.
@export_range(0.0, 3.0, 0.05) var allocation_hold: float = 0.6

## Fraction of the travel that passes before the allocation needle drops.
##
## [b]The needle does not need the camera to ARRIVE, only to LEAVE.[/b]
## [method MenuNodeView.play_allocation_spike] parents the spike to the view, in
## world space, so its on-screen height is `radius * SPIKE_HEIGHT_FACTOR * zoom`
## — at the root's authored radius 44 and [constant
## FrontmatterLayout.SPLASH_ZOOM] that is 845px of needle on a 960px screen whose
## node centre sits at 422, i.e. half of it off the top, which is what shipped.
## It fits whole once `264 * zoom <= 422`, so from zoom 1.6 down; [method
## FrontmatterCamera.ease_travel] is a cubic ease-out on the interpolated SCALE
## and crosses that at `t = 0.18`. The default clears it with room, and the root
## still reads at ~1.5x hero size when the needle lands, so the splash keeps the
## scale the owner asked for (2026-08-26, [i]"zoom it in just a bit more — it's
## the SPLASH"[/i]).
##
## [b]A fraction, not seconds[/b] — the same shape as [member
## FrontmatterRoot.panel_lead], and for the same reason. What the spike needs is
## a ZOOM; the zoom is a function of the eased clock, not of wall time, so an
## absolute delay would land at a different zoom the moment #578's tab retunes
## [member FrontmatterRoot.travel_duration].
##
## `0.0` fires it on the spot, which is the old behaviour and the comparison to
## judge this against.
@export_range(0.0, 1.0, 0.01) var spike_lead: float = 0.2

@onready var _prompt: Label = %Prompt

var _frontmatter: FrontmatterRoot = null
## One-way latch. A second press while the camera is still travelling must not
## re-trigger the advance — #574 names this explicitly, and without it a held
## key or a double click restarts the travel from wherever it had got to.
var _advanced: bool = false


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


## Allocate the root: travel the camera out to tree zoom, light the root up, and
## get out of the way. Idempotent by the latch — later calls do nothing at all.
##
## Public because it is the whole behaviour of this node, and a test that has to
## synthesize an [InputEventKey] to reach it would be testing Godot's input
## routing rather than this decision. The input handlers below are thin wrappers.
func advance() -> void:
	if _advanced:
		return
	_advanced = true
	visible = false
	_allocate_root()
	if _hold_seconds() <= 0.0:
		_travel()
	else:
		get_tree().create_timer(_hold_seconds()).timeout.connect(_travel)
	advanced.emit()


## Lights the root up — the half of the advance that happens on the spot.
##
## [b]The allocation is done HERE rather than left to [method
## FrontmatterRoot.focus]'s `_sync_allocation`.[/b] Those two used to be the same
## call, which is why the camera left the instant the key was pressed: the root
## could not read as allocated until the travel that allocated it had already
## started. Splitting them is the whole of the hold. `focus` re-asserts the same
## flag when it arrives, so this is a lead, not a second source of truth.
##
## [b]And that lead is exactly why the needle is scheduled elsewhere.[/b] Writing
## the flag up front is what makes `_sync_allocation` see no transition and fire
## nothing when the travel starts — so the VFX has to be split off the flag to be
## delayed at all, or [member spike_lead] would simply hand the spike back to
## [FrontmatterRoot] at the one instant it must not fire. Flag here, needle in
## [method _drop_needle].
func _allocate_root() -> void:
	if _frontmatter == null or _frontmatter.tree == null:
		return
	var root_view := _frontmatter.view_for(_frontmatter.tree.root)
	if root_view == null:
		return
	root_view.allocated = true


## The second half: pull back out to the tree. Re-checks everything, because a
## timer fires a frame or more later and the world may have moved on.
##
## [b]The focus guard is the latch, extended over the hold.[/b] The latch stops a
## SECOND press re-focusing the root; without this, the FIRST press did it —
## "PRESS ANY BUTTON" invites mashing, so a player can press again during the
## hold, navigate into SINGLE PLAYER, and be yanked home when the timer fires.
## The menu is still on the root all through the hold (`build` left it there and
## nothing has moved it), so this only trips when the player got ahead — and then
## their own travel has already pulled the camera out of splash zoom, which is
## the outcome anyway.
func _travel() -> void:
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	if _frontmatter.tree == null:
		return
	if _frontmatter.focus_id != _frontmatter.tree.root:
		return
	_frontmatter.focus(_frontmatter.tree.root)
	_drop_needle()


## Schedules the allocation needle for [member spike_lead] into the travel the
## caller has just started.
##
## [b]A fixed logical delay off the travel's own duration, never an await on the
## camera or on the spike's own tween[/b] — `.claude/rules/presentation-clock.md`,
## the same rule [member allocation_hold] answers to. Retuning
## [constant AllocationVFX.SPIKE_DURATION] must not silently retune the splash.
func _drop_needle() -> void:
	var delay := _spike_delay()
	if delay <= 0.0:
		_play_spike()
		return
	get_tree().create_timer(delay).timeout.connect(_play_spike)


## Seconds into the travel the needle drops. Collapsed to nothing by the
## accessibility setting exactly as [method _hold_seconds] is — and correct
## there for a second reason: `reduce_motion` makes [method
## FrontmatterRoot.focus] snap straight to [constant
## FrontmatterLayout.TREE_ZOOM], where the needle already fits whole.
func _spike_delay() -> float:
	if _frontmatter == null or _frontmatter.reduce_motion:
		return 0.0
	return spike_lead * _frontmatter.travel_duration


## Plays the game's own allocation spike on the root, re-checking everything —
## a timer fires a frame or more later and the world may have moved on, the same
## caution [method _travel] takes.
func _play_spike() -> void:
	if _frontmatter == null or not is_instance_valid(_frontmatter):
		return
	if _frontmatter.tree == null:
		return
	var root_view := _frontmatter.view_for(_frontmatter.tree.root)
	if root_view != null:
		root_view.play_allocation_spike()


## How long to hold. Collapsed to nothing by the accessibility setting, exactly
## as [member FrontmatterRoot.travel_duration] is — a player who asked for no
## motion is not asking for a pause where the motion used to be.
func _hold_seconds() -> float:
	if _frontmatter != null and _frontmatter.reduce_motion:
		return 0.0
	return allocation_hold


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
