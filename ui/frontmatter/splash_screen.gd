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
	if _frontmatter != null and _frontmatter.tree != null:
		_frontmatter.focus(_frontmatter.tree.root)
	advanced.emit()


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
